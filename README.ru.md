# fox

Библиотека для работы с RabbitMQ построенная поверх [amqp_client](https://github.com/jbrisbin/amqp_client) (форк, поддерживающий сборку ребаром).

Библиотека добавляет функциональность, которой нет в amqp_client и предлагает более удобный АПИ.


## Пул соединений

**fox** позволяет создать один или несколько пулов соединений, контролирует состояние соединений, при необходимости осуществляет реконнект прозрачно для пользователя.  Реконнект происходит с exponential backoff -- нарастающим таймаутом между попытками соединения.

Вызов **fox:create_connection_pool(PoolName, Params)** создает пул из нескольких соединений (по умолчанию 5) с заданными параметрами.  Имя может быть _atom()_, _string()_ или _binary()_.  Параметры соединения могут быть записью [#amqp_params_network{}](https://github.com/jbrisbin/amqp_client/blob/master/include/amqp_client.hrl#L25) либо _map()_ с такими же полями.

```erlang
Params = #{host => "localhost",
           port => 5672,
           virtual_host => <<"/">>,
           username => <<"guest">>,
           password => <<"guest">>},
fox:create_connection_pool(my_pool, Params),
```

Вызов **fox:close_connection_pool(PoolName)** закрывает все соединения и удаляет пул.

Перед созданием пула можно проверить параметры на валидность. Это делается вызовом **fox:validate_params_network(Params)**. Параметры соединения могут быть записью _#amqp\_params\_network{}_ или _map()_. Если параметры позволяют соединится с RabbitMQ, функция возвращает _ok_, иначе функция возвращает _{error, Reason}_.


## Работа с каналами

Во многих АПИ для работы с RabbitMQ требуется канал. Запросить канал можно вызовом **fox:get_channel(PoolName)**. Функция возвращает _{ok, ChannelPid}_ либо _{error, Reason}_.

```erlang
{ok, Channel} = fox:get_channel(my_pool),
fox:declare_exchange(Channel, <<"my_exchange">>)),
fox:declare_queue(Channel, <<"my_queue">>)),
fox:bind_queue(Channel, <<"my_queue">>, <<"my_exchange">>, <<"my_key">>)),
```


## Обертки над amqp_channel:call/cast

В библиотеке **amqp_client** взаимодействие с RabbitMQ большей частью осуществляется через вызовы **amqp_channel:call/cast**. Возможные действия и их параметры определяются записями, такими как: _#'basic.publish'{}_, _#'exchange.declare'{}_, _#'queue.bind'{}_ и т.д. Полный их список можно посмотреть в [rabbit_framing.hrl](https://github.com/jbrisbin/rabbit_common/blob/master/include/rabbit_framing.hrl). Примеры использования **amqp_channel:call/cast** и этих записей можно посмотреть в документации [Erlang AMQP Client library](http://www.rabbitmq.com/erlang-client-user-guide.html)

Для части из этих операций **fox** предлагает обертки с упрощенным АПИ. Например, вместо кода:

```erlang
BPublish = #'basic.publish'{exchange = Exchange, routing_key = RKey},
Message = #amqp_msg{payload = <<"foobar">>},
amqp_channel:cast(Channel, BPublish, Message)
```

можно использовать:

```erlang
fox:publish(Channel, Exchange, RKey, <<"foobar">>)
```

Или вместо кода:
```erlang
BPublish = #'basic.publish'{exchange = Exchange, routing_key = RKey},
Props = #'P_basic'{delivery_mode = 2}, %% persistent message
Message = #amqp_msg{props = Props, payload = <<"foobar">>},
amqp_channel:cast(Channel, BPublish, Message)
```

можно использовать:

```erlang
fox:publish(Channel, Exchange, RKey, <<"foobar">>, #{delivery_mode => 2})
```

Такие оберки есть для _publish_, _declare\_exchange_, _delete\_exchange_, _declare\_queue_, _delete\_queue_, _bind\_queue_, _unbind\_queue_ и _qos_.


## Публикация

Опубликовать сообщение можно с помощью вызова **fox:publish**. Первым аргументом передается либо _pid()_ канала, либо имя пула соединений.

```erlang
fox:publish(my_pool, Exchange, RougingKey, <<"Message">>)
```


## Подписка

Пожалуй, самое неудобное в работе с **amqp_client**, это подписка. **amqp_client:subscribe/3** принимает Pid процесса-клиента и посылает ему сообщения. Для обработки этих сообщений нужно создавать отдельный gen_server.

**fox** предлагает другой вариант, похожий на хендлеры для cowboy. Пользователь создает модуль, реализующий behaviour **fox_subs_worker**, и передает этот модуль в **fox:subscribe**. Далее **fox** создает канал, подписывается в amqp_client:subscribe, получает сообщения и передает их для обработки в пользовательский модуль.

```erlang
{ok, Ref} = fox:subscribe(my_pool, <<"my_queue">>, my_callback_module, CallbackInitArgs)
```

Первый аргумент -- имя пула. Второй аргумент --  очередь, на которую нужно подписаться. Очередь может быть задана либо просто именем (_binary()_), либо записью _#'basic.consume'{}_. Запись используется, если требуются дополнительные параметры очереди (exclusive, nowait, no\_ack etc). Третий аргумент -- имя модуля. Четвертый -- аргументы для инициализации модуля. **subscribe** возвращает _reference()_, по которому потом можно будет отменить подписку.

Callback модуль должен определить 3 функции:

**init(Channel, Args)** -- вызывается после создания канала, но до подписки его на сообщения. Здесь можно, например, создать нужные exchanges, queues и bingings. Функция должна вернуть некий _State_, который затем будет передаваться в _handle_ и _terminate_.

```erlang
init(Channel, Args) ->
    ok = fox:declare_exchange(Channel, Exchange),
    ok = fox:declare_queue(Channel, Queue),
    ok = fox:bind_queue(Channel, Queue, Exchange, RoutingKey),
    State = ...,
    {ok, State}.
```

**handle(Data, ChannelPid, State)** -- вызывается каждый раз, когда приходят какие-то данные из очередей. Данные можно обработать и послать на них _basic.ack_ или _basic.reject_, или проигнорировать. Функция должна вернуть измененный _state_.

```erlang
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, Channel, State) ->
    do_something,
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};
```

**terminate(ChannelPid, State)** -- вызывается на _unsubscribe_ или при остановке пула. Здесь можно освободить ресурсы, убрать exchanges, queues и bingings и т.д.

```erlang
terminate(Channel, State) ->
    fox:unbind_queue(Channel, Queue, Exchange, RoutingKey),
    fox:delete_queue(Channel, Queue)
    fox:delete_exchange(Channel, Exchange),
    ok.
```

Библиотека включает пример модуля, реализующего  **fox_subs_worker**: [sample_subs_callback](src/subscription/sample_subs_callback.erl)

Вызов **fox:unsubscribe(PoolName, Ref)** удаляет подписку.
