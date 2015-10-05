# fox

Библиотека для работы с RabbitMQ построенная поверх
[amqp_client](https://github.com/jbrisbin/amqp_client)
(форк, поддерживающий сборку ребаром).

Библиотека добавляет функциональность, которой нет в amqp_client
и предлагает более удобный АПИ.


## Пул соединений

**fox** позволяет создать один или несколько пулов соединений,
контролирует состояние соединений, при необходимости осуществляет
реконнект прозрачно для пользователя.

Вызов **fox:create_connection_pool(ConnectionName, Params)** создает пул из 5 соединений с заданными параметрами.
Имя может быть _atom()_, _string()_ или _binary()_.
Параметры соединения могут быть записью
[#amqp_params_network{}](https://github.com/jbrisbin/amqp_client/blob/master/include/amqp_client.hrl#L25)
либо _map()_ с такими же полями.
Размер пула можно изменить настройкой _connection\_pool\_size_.

Вызов **fox:close_connection_pool(ConnectionName)** закрывает все соединения и удаляет пул.

Перед созданием пула можно проверить параметры на валидность.
Это делается вызовом **fox:validate_params_network(Params)**.
Параметры соединения могут быть записью _#amqp\_params\_network{}_ или _map()_.
Если параметры позволяют соединится с RabbitMQ, функция возвращает _ok_,
иначе функция возвращает _{error, Reason}_.


## Работа с каналами

Во всех АПИ для работы с RabbitMQ (кроме fox:subscribe/2,3) требуется канал.
Запросить канал можно вызовом **fox:create_channel(ConnectionName)**.
При этом пул выбирает соединение, где открыто меньше всего каналов, и создает
новый канал в этом соединении. Функция возвращает _{ok, ChannelPid}_ либо _{error, Reason}_.

Пользователь должен закрыть канал, если канал больше не
нужен. Библиотека сама не может определить, какие каналы используются,
а какие нет.  Если пользователь будет динамически создавать каналы, и
не будет закрывать их, это приведет к утечке ресурсов.

Канал закрывается вызовом **amqp_channel:close(ChannelPid)**.


## Обертки над amqp_channel:call/cast

В библиотеке **amqp_client** взаимодействие с RabbitMQ большей частью осуществляется
через вызовы **amqp_channel:call/cast**. Возможные действия и их параметры определяются
записями, такими как: _basic.publish_, _exchange.declare_, _queue.bind_ и т.д.
Полный их список можно посмотреть в
[rabbit_framing.hrl](https://github.com/jbrisbin/rabbit_common/blob/master/include/rabbit_framing.hrl).
Примеры использования **amqp_channel:call/cast** и этих записей можно посмотреть в документации
[Erlang AMQP Client library](http://www.rabbitmq.com/erlang-client-user-guide.html)

Для части из этих операций **fox** предлагает обертки с упрощенным АПИ.
Например, вместо кода:

```erlang
Payload = <<"foobar">>,
Publish = #'basic.publish'{exchange = X, routing_key = Key},
Message = #amqp_msg{payload = Payload},
amqp_channel:cast(ChannelPid, Publish, Message)
```

можно использовать:

```erlang
fox:publish(ChannelPid, X, Key, <<"foobar">>)
```

Или вместо кода:
```erlang
Payload = <<"foobar">>,
Publish = #'basic.publish'{exchange = X, routing_key = Key},
Props = #'P_basic'{delivery_mode = 2}, %% persistent message
Message = #amqp_msg{props = Props, payload = Payload},
amqp_channel:cast(ChannelPid, Publish, Message)
```

можно использовать:

```erlang
fox:publish(ChannelPid, X, Key, <<"foobar">>, #{delivery_mode => 2})
```

Такие оберки есть для _publish_, _declare\_exchange_, _delete\_exchange_,
_declare\_queue_, _delete\_queue_, _bind\_queue_, _unbind\_queue_.


## Подписка

Пожалуй, самое неудобное в работе с **amqp_client**, это подписка.
**amqp_client:subscribe/3** принимает Pid процесса-клиента и посылает ему сообщения.
Для обработки этих сообщений нужно создавать отдельный gen_server.

**fox** предлагает другой вариант.
Пользователь создает модуль, реализующий behaviour **fox_channel_consumer**,
и передает этот модуль в **fox:subscribe(ConnectionName, Module, Args)**.
Далее **fox** создает канал, подписывается в amqp_client:subscribe, получает сообщения
и передает их для обработки в пользовательский модуль.

Модуль должен определить 3 функции:

**init(ChannelPid, Args)** --
вызывается после создания канала, но до подписки его на сообщения.
Здесь можно, например, создать нужные exchanges, queues и bingings.
Функция должна вернуть список очередей, на которые нужно подписаться,
(в виде объектов _basic.consume_)
и _state_, который затем будет передаваться в _handle_ и _terminate_.

```erlang
init(ChannelPid, Args) ->
    State = my_state,
    ...
    ok = fox:declare_exchange(ChannelPid, Exchange),
    ok = fox:declare_queue(ChannelPid, Queue1),
    ok = fox:bind_queue(ChannelPid, Queue1, Exchange, RoutingKey1),
    ok = fox:declare_queue(ChannelPid, Queue2),
    ok = fox:bind_queue(ChannelPid, Queue2, Exchange, RoutingKey2),
    BC1 = #'basic.consume'{queue = Queue1},
    BC2 = #'basic.consume'{queue = Queue2},
    {{subscribe, [BC1, BC2]}, State}.
```

**handle(Data, ChannelPid, State)** --
вызывается каждый раз, когда приходят какие-то данные из очередей.
Данные можно обработать и послать на них _basic.ack_ или _basic.reject_,
или проигнорировать. Функция должна вернуть измененный _state_.

```erlang
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, State) ->
    ...
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};
```

**terminate(ChannelPid, State)** --
вызывается на _unsubscribe_ или при остановке пула.
Здесь можно освободить ресурсы, убрать exchanges, queues и bingings и т.д.

```erlang
terminate(ChannelPid, State) ->
    ...
    fox:unbind_queue(ChannelPid, Queue, Exchange, RoutingKey),
    fox:delete_queue(ChannelPid, Queue)
    fox:delete_exchange(ChannelPid, Exchange),
    ok.
```

Библиотека включает пример модуля, реализующего  **fox_channel_consumer**:
[sample_channel_consumer](blob/master/src/sample_channel_consumer.erl)


Вызов **fox:unsubscribe(ConnectionName, ChannelPid)** удаляет подписку,
и закрывает канал.
