# fox

Client library for RabbitMQ build on top of [amqp_client](https://github.com/rabbitmq/rabbitmq-erlang-client).


## Connection Pool

**fox** allows to create one or seleral connection pools, monitors connections inside pool and reconnects them if needed.

**fox:create_connection_pool(PoolName, ConenctionParams)** creates pool with several connections (5 by default). PoolName should be an `atom()`, `string()` or `binary()`. ConnectionParams should be record [#amqp_params_network{}](https://github.com/jbrisbin/amqp_client/blob/master/include/amqp_client.hrl#L25) or `map()` with the same fields.

```erlang
Params = #{host => "localhost",
           port => 5672,
           virtual_host => <<"/">>,
           username => <<"guest">>,
           password => <<"guest">>},
fox:create_connection_pool(my_pool, Params),
```

**fox:close_connection_pool(PoolName)** closes all connections and removes the pool.

Before stating a pool you can check your connection params by calling **fox:validate_params_network(Params)**. If params are valid to connect to RabbitMQ, function returns `ok`, otherwise it returns `{error, Reason}`.


## Working with Channels

Many APIs need a channel. You can get channel with **fox:get_channel(PoolName)**. Function returns `{ok, ChannelPid}` or `{error, Reason}`.

```erlang
{ok, Channel} = fox:get_channel(my_pool),
fox:declare_exchange(Channel, <<"my_exchange">>)),
fox:declare_queue(Channel, <<"my_queue">>)),
fox:bind_queue(Channel, <<"my_queue">>, <<"my_exchange">>, <<"my_key">>)),
```


## Wrappers for amqp_channel:call/cast

**amqp_client** library communicates with RabbitMQ with **amqp_channel:call/cast** calls. It uses records like `#'basic.publish'{}`, `#'exchange.declare'{}`, `#'queue.bind'{}` etc. And this is not very convenient.

Here you can find the full list of records: [rabbit_framing.hrl](https://github.com/jbrisbin/rabbit_common/blob/master/include/rabbit_framing.hrl).

**fox** provides wrappers for most often used actions. For example, instead of

```erlang
BPublish = #'basic.publish'{exchange = Exchange, routing_key = RKey},
Message = #amqp_msg{payload = <<"foobar">>},
amqp_channel:cast(Channel, BPublish, Message)
```

you can use

```erlang
fox:publish(Channel, Exchange, RKey, <<"foobar">>)
```

And instead of

```erlang
BPublish = #'basic.publish'{exchange = Exchange, routing_key = RKey},
Props = #'P_basic'{delivery_mode = 2}, %% persistent message
Message = #amqp_msg{props = Props, payload = <<"foobar">>},
amqp_channel:cast(Channel, BPublish, Message)
```

you can use

```erlang
fox:publish(Channel, Exchange, RKey, <<"foobar">>, #{delivery_mode => 2})
```
There are wrappers for `publish`, `declare_exchange`, `delete_exchange`, `declare_queue`, `delete_queue`, `bind_queue`, `unbind_queue` and `qos`.


## Publishing

To publish a message to RabbitMQ use **fox:publish**. First agrument should be channel pid or pool name.

```erlang
fox:publish(my_pool, Exchange, RougingKey, <<"Message">>)
```


## Subscription

The most sophisticated part of working with **amqp_channel** is subscription. You need gen\_server process to accept messages, and send pid of this process as argument to **amqp_client:subscribe/3**.

**fox** works differently. First you create callback module implementing **fox_subs_worker** behaviour. This is something similar to cowboy handler. Then you call `fox:subscribe`. **fox** creates channel and new process for you module, subscribes to queues and routes messages to your callback module.

```erlang
{ok, Ref} = fox:subscribe(my_pool, <<"my_queue">>, my_callback_module, CallbackInitArgs)
```

The first argument is a pool name. The second argument is queue. Queue can be a queue name (`binary()`) or a `#'basic.consume'{}` record. Use `basic.consume` if you need to defined some additional parameters for queue like `exclusive`, `nowait`, `no_ack` etc. The forth argument (Args) used to init you callback module. **subscribe** returns `reference()` needed fo unsubscribe.

**fox_subs_worker** behaviour includes 3 functions:

**init(ChannelPid, Args)** gets channel pid and Args (the forth argument to `fox:subscribe`). Here you can do any initialization steps, like creating exchanges, queues and bindings. `init` returns some state which will be later used in other callbacks.

```erlang
init(Channel, Args) ->
    ok = fox:declare_exchange(Channel, Exchange),
    ok = fox:declare_queue(Channel, Queue),
    ok = fox:bind_queue(Channel, Queue, Exchange, RoutingKey),
    State = ...,
    {ok, State}.
```

**handle(Data, ChannelPid, State)** called each time new message arrives. Here you can process message, reply with `#'basic.ack'{}` or `#'basic.reject'{}`, or don't reply at all.  Function should return a new state.

```erlang
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, State) ->
    do_something,
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};
```

**terminate(ChannelPid, State)** is called on `unsubscribe` or pool closing. Here you can free resources, remove exchanges and queue.

```erlang
terminate(ChannelPid, State) ->
    fox:unbind_queue(ChannelPid, Queue, Exchange, RoutingKey),
    fox:delete_queue(ChannelPid, Queue)
    fox:delete_exchange(ChannelPid, Exchange),
    ok.
```

Here is a sample callback module: [sample_subs_callback](src/subscription/sample_subs_callback.erl)

**fox:unsubscribe(PoolName, Ref)** removes subscription.
