# fox

Client lib for RabbitMQ build on top of
[amqp_client](https://github.com/jbrisbin/amqp_client)
(rebar-friendly fork).


## Connection Pool

**fox** allows to create one or seleral connection pools,
monitors connections inside pool and reconnects if needed.

**fox:create_connection_pool(PoolName, ConenctionParams)** creates pool of 5 connections.
PoolName should be _atom()_, _string()_ or _binary()_.
ConnectionParams should be record
[#amqp_params_network{}](https://github.com/jbrisbin/amqp_client/blob/master/include/amqp_client.hrl#L25)
or _map()_ with the same fields.

Pool size is defined by _connection\_pool\_size_ application settings.

**fox:close_connection_pool(PoolName)** closes all connections and remove pool.

Before stating the pool you can check your connection params with call to
**fox:validate_params_network(Params)**.
If params are valid to connect to RabbitMQ, function returns _ok_,
otherwise it returns _{error, Reason}_.


## Working with Channels

Every API (except fox:subscribe/2,3 and fox:publish/4,5) needs a channel.
You can get channel with **fox:create_channel(PoolName)**.

Pool looks for connection which has less channels and creates new channel on this connection.
Function returns _{ok, ChannelPid}_ or _{error, Reason}_.

You should close channel when no longer needed. Fox wouldn't do it itself.
If you only create channels but don't close them you will get a leak of resources.
To prevent node crashing because of such a leak fox uses
**max_channels_per_connection** application settings.
Default value is 100 channels per connection.

**amqp_channel:close(ChannelPid)** closes the channel.


## Wrappers for amqp_channel:call/cast

**amqp_client** library communicates with RabbitMQ with **amqp_channel:call/cast** calls.
It uses records like _#'basic.publish'{}_, _#'exchange.declare'{}_, _#'queue.bind'{}_ etc.
And this is not very convenient.

Full list of this records you can find here:
[rabbit_framing.hrl](https://github.com/jbrisbin/rabbit_common/blob/master/include/rabbit_framing.hrl).

**fox** provides wrappers for most ofter used actions.
For example, instead of

```erlang
Payload = <<"foobar">>,
Publish = #'basic.publish'{exchange = X, routing_key = Key},
Message = #amqp_msg{payload = Payload},
amqp_channel:cast(ChannelPid, Publish, Message)
```

you can use

```erlang
fox:publish(ChannelPid, X, Key, <<"foobar">>)
```

And insread of

```erlang
Payload = <<"foobar">>,
Publish = #'basic.publish'{exchange = X, routing_key = Key},
Props = #'P_basic'{delivery_mode = 2}, %% persistent message
Message = #amqp_msg{props = Props, payload = Payload},
amqp_channel:cast(ChannelPid, Publish, Message)
```

you can use

```erlang
fox:publish(ChannelPid, X, Key, <<"foobar">>, #{delivery_mode => 2})
```

There are wrappers for _publish_, _declare\_exchange_, _delete\_exchange_,
_declare\_queue_, _delete\_queue_, _bind\_queue_, _unbind\_queue_.


## Publishing

To publish a message to RabbitMQ use **fox:publish**.
First agrument should be channel pid or pool name.

fox has it own pool of channels ready to publish messages.
You can use it if you don't want to create, keep and monitor channels.

```erlang
fox:publish(my_pool, Exchange, RougingKey, <<"Message">>)
```

Pool has 20 channels by default.
Use **publish_pool_size** application settings if you want to change it.


## Subscription

The most sophisticated part of working with **amqp_channel** lib is subscription.
You need gen\_server process to accept messages, and send pid of this process
as argument to **amqp_client:subscribe/3**.

**fox** provides other cowboy-like way.

You should create callback module implementing **fox_subscription_worker** behaviour.
This is something similar to cowboy handler.

Then call **fox:subscribe(PoolName, Queues, ModuleName, Args)**.
**fox** creates channel process and new process for you module, monitors them both, restarts them
on reconnect or crash, subscribes to queues, routes messages and acknoledges them.
You shouldn't care about all this things. You only need to implement **fox_subscription_worker** behaviour.

The second argument (Queues) can be single queue or list of queues. And queue can be
set as simple binary value -- queue name, or as _#'basic.consume'{}_ record.
Use second option when you need to defined some additional params for queue
like exclusive, nowait, no_ack etc.

The forth argument (Args) used to init you callback module.

**fox_subscription_worker** behaviour includes 3 functions:

**init(ChannelPid, Args)** gets channel pid and Args (forth argument to fox:subscribe).
Here you can do any initialization steps, like, for example, creating exchanges and queues and bindings.
An it should create some state which will be used in other callbacks.

```erlang
init(ChannelPid, Args) ->
    State = my_state,
    ...
    ok = fox:declare_exchange(ChannelPid, Exchange),
    ok = fox:declare_queue(ChannelPid, Queue1),
    ok = fox:bind_queue(ChannelPid, Queue1, Exchange, RoutingKey1),
    ok = fox:declare_queue(ChannelPid, Queue2),
    ok = fox:bind_queue(ChannelPid, Queue2, Exchange, RoutingKey2),
    {ok, State}
```

**handle(Data, ChannelPid, State)** called each time new message arrives.
Here you can process message, reply with _#'basic.ack'{}_ or
_#'basic.reject'{}_, or don't reply at all.  Function should return
new state.

```erlang
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, State) ->
    ...
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    do_something,
    {ok, State};
```

**terminate(ChannelPid, State)** called on _unsubscribe_ or pool closing.
Here you can free resources, remove exchanges and queue.

```erlang
terminate(ChannelPid, State) ->
    ...
    fox:unbind_queue(ChannelPid, Queue, Exchange, RoutingKey),
    fox:delete_queue(ChannelPid, Queue)
    fox:delete_exchange(ChannelPid, Exchange),
    ok.
```

Here is a sample callback module:
[sample_subscription_callback](src/sample_subscription_callback.erl)


**fox:unsubscribe(PoolName, ChannelPid)** unsubscribes and closes channel.
