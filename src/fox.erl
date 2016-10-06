-module(fox).

-export([validate_params_network/1,
         create_connection_pool/2,
         create_connection_pool/3,
         create_connection_pool/4,
         close_connection_pool/1,
         create_channel/1,
         subscribe/3, subscribe/4, unsubscribe/2,
         declare_exchange/2, declare_exchange/3,
         delete_exchange/2, delete_exchange/3,
         declare_queue/2, declare_queue/3,
         delete_queue/2, delete_queue/3,
         bind_queue/4, bind_queue/5,
         unbind_queue/4, unbind_queue/5,
         publish/4, publish/5,
         qos/2,
         test_run/0]).

-include("fox.hrl").


%%% module API

-spec validate_params_network(#amqp_params_network{} | map()) -> ok | {error, term()}.
validate_params_network(Params) when is_map(Params) ->
    validate_params_network(fox_utils:map_to_params_network(Params));

validate_params_network(Params) ->
    true = fox_utils:validate_params_network_types(Params),
    case amqp_connection:start(Params) of
        {ok, Connection} -> amqp_connection:close(Connection), ok;
        {error, Reason} -> {error, Reason}
    end.


-spec create_connection_pool(pool_name(), #amqp_params_network{} | map()) -> ok.
create_connection_pool(PoolName, Params) ->
    {ok, PoolSize} = application:get_env(fox, connection_pool_size),
    create_connection_pool(PoolName, Params, PoolSize).


-spec create_connection_pool(pool_name(), #amqp_params_network{} | map(), integer()) -> ok.
create_connection_pool(PoolName, #amqp_params_network{} = Params, PoolSize) ->
    create_connection_pool(PoolName, Params, #{}, PoolSize);
create_connection_pool(PoolName, Params, PoolSize) when is_map(Params) ->
    create_connection_pool(PoolName, fox_utils:map_to_params_network(Params), Params, PoolSize).


-spec create_connection_pool(pool_name(), #amqp_params_network{}, integer(), map()) -> ok.
create_connection_pool(PoolName, #amqp_params_network{} = ConnectionParams, OtherParams, PoolSize) ->
    true = fox_utils:validate_params_network_types(ConnectionParams),
    PoolName2 = fox_utils:name_to_atom(PoolName),
    fox_connection_pool_sup:start_pool(PoolName2, ConnectionParams, OtherParams, PoolSize),
    ok.


-spec close_connection_pool(pool_name()) -> ok | {error, term()}.
close_connection_pool(PoolName) ->
    PoolName2 = fox_utils:name_to_atom(PoolName),
    fox_connection_pool_sup:stop_pool(PoolName2).


-spec create_channel(pool_name()) -> {ok, pid()} | {error, term()}.
create_channel(PoolName) ->
    PoolName2 = fox_utils:name_to_atom(PoolName),
    fox_connection_pool_sup:create_channel(PoolName2).


-spec subscribe(pool_name(), subscribe_queue() | [subscribe_queue()], module()) ->
                       {ok, reference()} | {error, term()}.
subscribe(PoolName, Queues, ConsumerModule) ->
    subscribe(PoolName, Queues, ConsumerModule, []).


-spec subscribe(pool_name(), subscribe_queue() | [subscribe_queue()], module(), list()) ->
                       {ok, reference()} | {error, term()}.
subscribe(PoolName, Queue, ConsumerModule, ConsumerModuleArgs) when not is_list(Queue) ->
    subscribe(PoolName, [Queue], ConsumerModule, ConsumerModuleArgs);

subscribe(PoolName, Queues, ConsumerModule, ConsumerModuleArgs) ->
    true = fox_utils:validate_consumer_behaviour(ConsumerModule),
    PoolName2 = fox_utils:name_to_atom(PoolName),
    fox_connection_pool_sup:subscribe(PoolName2, Queues, ConsumerModule, ConsumerModuleArgs).


-spec unsubscribe(pool_name(), reference()) -> ok | {error, term()}.
unsubscribe(PoolName, Ref) ->
    PoolName2 = fox_utils:name_to_atom(PoolName),
    fox_connection_pool_sup:unsubscribe(PoolName2, Ref).


-spec declare_exchange(pid(), binary()) -> ok | {error, term()}.
declare_exchange(ChannelPid, Name) when is_binary(Name) ->
    declare_exchange(ChannelPid, Name, maps:new()).


-spec declare_exchange(pid(), binary(), map()) -> ok | {error, term()}.
declare_exchange(ChannelPid, Name, Params) ->
    ExchangeDeclare = fox_utils:map_to_exchange_declare(Params),
    ExchangeDeclare2 = ExchangeDeclare#'exchange.declare'{exchange = Name},
    case fox_utils:channel_call(ChannelPid, ExchangeDeclare2) of
        #'exchange.declare_ok'{} -> ok;
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec delete_exchange(pid(), binary()) -> ok | {error, term()}.
delete_exchange(ChannelPid, Name) when is_binary(Name) ->
    delete_exchange(ChannelPid, Name, maps:new()).


-spec delete_exchange(pid(), binary(), map()) -> ok | {error, term()}.
delete_exchange(ChannelPid, Name, Params) ->
    ExchangeDelete = fox_utils:map_to_exchange_delete(Params),
    ExchangeDelete2 = ExchangeDelete#'exchange.delete'{exchange = Name},
    case fox_utils:channel_call(ChannelPid, ExchangeDelete2) of
        #'exchange.delete_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec declare_queue(pid(), binary()) -> ok | #'queue.declare_ok'{} | {error, term()}.
declare_queue(ChannelPid, Name) when is_binary(Name) ->
    declare_queue(ChannelPid, Name, maps:new()).


-spec declare_queue(pid(), binary(), map()) -> ok | #'queue.declare_ok'{} | {error, term()}.
declare_queue(ChannelPid, Name, Params) ->
    QueueDeclare = fox_utils:map_to_queue_declare(Params),
    QueueDeclare2 = QueueDeclare#'queue.declare'{queue = Name},
    case fox_utils:channel_call(ChannelPid, QueueDeclare2) of
        ok -> ok;
        #'queue.declare_ok'{} = Reply -> Reply;
        {error, Reason} -> {error, Reason}
    end.


-spec delete_queue(pid(), binary()) -> #'queue.delete_ok'{} | {error, term()}.
delete_queue(ChannelPid, Name) when is_binary(Name) ->
    delete_queue(ChannelPid, Name, maps:new()).


-spec delete_queue(pid(), binary(), map()) -> #'queue.delete_ok'{} | {error, term()}.
delete_queue(ChannelPid, Name, Params) ->
    QueueDelete = fox_utils:map_to_queue_delete(Params),
    QueueDelete2 = QueueDelete#'queue.delete'{queue = Name},
    case fox_utils:channel_call(ChannelPid, QueueDelete2) of
        ok -> ok;
        #'queue.delete_ok'{} = Reply -> Reply;
        {error, Reason} -> {error, Reason}
    end.


-spec bind_queue(pid(), binary(), binary(), binary()) -> ok | {error, term()}.
bind_queue(ChannelPid, Queue, Exchange, RoutingKey) ->
    bind_queue(ChannelPid, Queue, Exchange, RoutingKey, maps:new()).


-spec bind_queue(pid(), binary(), binary(), binary(), map()) -> ok | {error, term()}.
bind_queue(ChannelPid, Queue, Exchange, RoutingKey, Params) ->
    QueueBind = fox_utils:map_to_queue_bind(Params),
    QueueBind2 = QueueBind#'queue.bind'{queue = Queue,
                                        exchange = Exchange,
                                        routing_key = RoutingKey},
    case fox_utils:channel_call(ChannelPid, QueueBind2) of
        #'queue.bind_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec unbind_queue(pid(), binary(), binary(), binary()) -> ok | {error, term()}.
unbind_queue(ChannelPid, Queue, Exchange, RoutingKey) ->
    unbind_queue(ChannelPid, Queue, Exchange, RoutingKey, maps:new()).


-spec unbind_queue(pid(), binary(), binary(), binary(), map()) -> ok | {error, term()}.
unbind_queue(ChannelPid, Queue, Exchange, RoutingKey, Params) ->
    QueueUnbind = fox_utils:map_to_queue_unbind(Params),
    QueueUnbind2 = QueueUnbind#'queue.unbind'{queue = Queue,
                                              exchange = Exchange,
                                              routing_key = RoutingKey},
    case fox_utils:channel_call(ChannelPid, QueueUnbind2) of
        #'queue.unbind_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec publish(pool_name() | pid(), binary(), binary(), binary()) -> ok | {error, term()}.
publish(PoolOrChannel, Exchange, RoutingKey, Payload) ->
    publish(PoolOrChannel, Exchange, RoutingKey, Payload, maps:new()).


-spec publish(pool_name() | pid(), binary(), binary(), binary(), map()) -> ok | {error, term()}.
publish(PoolOrChannel, Exchange, RoutingKey, Payload, Params) when is_binary(Payload) ->
    Publish = fox_utils:map_to_basic_publish(Params#{exchange => Exchange, routing_key => RoutingKey}),
    PBasic = fox_utils:map_to_pbasic(Params),
    Message = #amqp_msg{payload = Payload, props = PBasic},

    PublishFun = case Params of
                     #{synchronous := true} -> channel_call;
                     _ -> channel_cast
                 end,
    if
        is_pid(PoolOrChannel) -> fox_utils:PublishFun(PoolOrChannel, Publish, Message);
        true -> PoolName = fox_utils:name_to_atom(PoolOrChannel),
                case fox_connection_pool_sup:get_publish_channel(PoolName) of
                    {ok, Channel} -> fox_utils:PublishFun(Channel, Publish, Message);
                    {error, Reason} -> {error, Reason}
                end
    end.


-spec qos(pool_name() | pid(), map()) -> ok | {error, term()}.
qos(PoolOrChannel, Params) ->
    QoS = fox_utils:map_to_basic_qos(Params),
    if
        is_pid(PoolOrChannel) ->
            #'basic.qos_ok'{} = amqp_channel:call(PoolOrChannel, QoS),
            ok;
        true -> PoolName = fox_utils:name_to_atom(PoolOrChannel),
            case fox_connection_pool_sup:get_publish_channel(PoolName) of
                {ok, Channel} ->
                    #'basic.qos_ok'{} = amqp_channel:call(Channel, QoS),
                    ok;
                {error, Reason} -> {error, Reason}
            end
    end.


-spec(test_run() -> ok).
test_run() ->
    application:ensure_all_started(fox),

    Params = #{host => "localhost",
               port => 5672,
               virtual_host => <<"/">>,
               username => <<"guest">>,
               password => <<"guest">>},

    ok = validate_params_network(Params),
    {error, {auth_failure, _}} = validate_params_network(Params#{username => <<"Bob">>}),

    create_connection_pool("test_pool", Params),
    qos("test_pool", #{prefetch_count => 10}),

    Q1 = #'basic.consume'{queue = <<"my_queue">>},
    Q2 = <<"other_queue">>,
    {ok, _Ref} = subscribe("test_pool", [Q1, Q2], sample_channel_consumer),

    timer:sleep(500),

    {ok, PChannel} = create_channel("test_pool"),
    publish(PChannel, <<"my_exchange">>, <<"my_key">>, <<"Hi there!">>),
    publish(PChannel, <<"my_exchange">>, <<"my_key_2">>, <<"Hello!">>),
    publish("test_pool", <<"my_exchange">>, <<"my_key">>, <<"Hello 3">>),
    publish("test_pool", <<"my_exchange">>, <<"my_key">>, <<"Hello 4">>),

    %% timer:sleep(1000),

    %% unsubscribe("test_pool", Ref),
    %% amqp_channel:close(PChannel),
    %% close_connection_pool("test_pool"),

    ok.
