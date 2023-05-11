-module(fox).

-export([validate_params_network/1,
         create_connection_pool/2,
         create_connection_pool/3,
         close_connection_pool/1,
         get_channel/1,
         subscribe/3, subscribe/4, unsubscribe/2,
         declare_exchange/2, declare_exchange/3,
         delete_exchange/2, delete_exchange/3,
         bind_exchange/4, bind_exchange/5,
         declare_queue/2, declare_queue/3,
         delete_queue/2, delete_queue/3,
         bind_queue/4, bind_queue/5,
         unbind_queue/4, unbind_queue/5,
         publish/4, publish/5,
         qos/2,
         test_run/0]).

-include("fox.hrl").


%%% module API

-spec validate_params_network(Params :: #amqp_params_network{} | map()) ->
    ok | {error, Reason :: term()}.
validate_params_network(Params) when is_map(Params) ->
    validate_params_network(fox_utils:map_to_params_network(Params));

validate_params_network(Params) ->
    true = fox_utils:validate_params_network_types(Params),
    case amqp_connection:start(Params) of
        {ok, Connection} -> amqp_connection:close(Connection), ok;
        {error, Reason} -> {error, Reason}
    end.


-spec create_connection_pool(pool_name(),
                             Params :: #amqp_params_network{} | map()) -> ok.
create_connection_pool(PoolName, Params) ->
    {ok, PoolSize} = application:get_env(fox, connection_pool_size),
    create_connection_pool(PoolName, Params, PoolSize).


-spec create_connection_pool(pool_name(),
                             Params :: #amqp_params_network{} | map(),
                             PoolSize :: integer()) -> ok.
create_connection_pool(PoolName0, Params, PoolSize) ->
    ConnectionParams = fox_utils:map_to_params_network(Params),
    true = fox_utils:validate_params_network_types(ConnectionParams),
    logger:notice("fox create pool ~s ~s",
        [PoolName0, fox_utils:params_network_to_str(ConnectionParams)]),
    PoolName = fox_utils:name_to_atom(PoolName0),
    {ok, _} = fox_sup:start_pool(PoolName, ConnectionParams, PoolSize),
    ok.


-spec close_connection_pool(pool_name()) -> ok | {error, not_found}.
close_connection_pool(PoolName0) ->
    PoolName = fox_utils:name_to_atom(PoolName0),
    case fox_sup:pool_exists(PoolName) of
        true ->
            logger:notice("fox stop pool ~s", [PoolName0]),
            fox_conn_pool:stop(PoolName),
            fox_pub_pool:stop(PoolName),
            fox_sup:stop_pool(PoolName);
        false -> {error, not_found}
    end.


-spec get_channel(pool_name()) -> {ok, pid()} | {error, Reason :: term()}.
get_channel(PoolName0) ->
    PoolName = fox_utils:name_to_atom(PoolName0),
    fox_pub_pool:get_channel(PoolName).


-spec subscribe(pool_name(), subscribe_queue(), module()) ->
    {ok, SubscriptionReference :: reference()} | {error, Reason :: term()}.
subscribe(PoolName, Queue, SubsModule) ->
    subscribe(PoolName, Queue, SubsModule, []).


-spec subscribe(pool_name(), subscribe_queue(), module(), list()) ->
    {ok, SubscriptionReference :: reference()}.
subscribe(PoolName0, BasicConsumeOrQueueName, SubsModule, SubsArgs) ->
    PoolName = fox_utils:name_to_atom(PoolName0),
    CPid = fox_conn_pool:get_conn_worker(PoolName),
    BasicConsume = 
        case BasicConsumeOrQueueName of
            #'basic.consume'{} = Consume -> Consume;
            Name when is_binary(Name) -> #'basic.consume'{queue = Name}
        end,
    SubsRef = make_ref(),
    Subs = #subscription{
              ref = SubsRef,
              pool_name = PoolName,
              conn_worker = CPid,
              basic_consume = BasicConsume,
              subs_module = SubsModule,
              subs_args = SubsArgs
            },
    {ok, _} = fox_subs_sup:start_subscriber(PoolName, Subs),
    {ok, SubsRef}.


-spec unsubscribe(pool_name(), SubscriptionReference :: reference()) ->
    ok | {error, Reason :: term()}.
unsubscribe(PoolName0, Ref) ->
    PoolName = fox_utils:name_to_atom(PoolName0),
    case fox_conn_pool:get_subs_meta(PoolName, Ref) of
        #subs_meta{conn_worker = CPid, subs_worker = SPid} ->
            fox_conn_worker:remove_subscriber(CPid, SPid),
            fox_conn_pool:remove_subs_meta(PoolName, Ref),
            fox_subs_worker:stop(SPid),
            ok;
        not_found -> {error, not_found}
    end.


-spec declare_exchange(Channel :: pid(), Name :: binary()) ->
    ok | {error, Reason :: term()}.
declare_exchange(ChannelPid, Name) when is_binary(Name) ->
    declare_exchange(ChannelPid, Name, maps:new()).


-spec declare_exchange(Channel :: pid(), Name :: binary(), Params :: map()) ->
    ok | {error, Reason :: term()}.
declare_exchange(ChannelPid, Name, Params) ->
    ExchangeDeclare = fox_utils:map_to_exchange_declare(Params),
    ExchangeDeclare2 = ExchangeDeclare#'exchange.declare'{exchange = Name},
    case fox_utils:channel_call(ChannelPid, ExchangeDeclare2) of
        #'exchange.declare_ok'{} -> ok;
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

-spec delete_exchange(Channel :: pid(),  Name :: binary()) ->
    ok | {error, Reason :: term()}.
delete_exchange(ChannelPid, Name) when is_binary(Name) ->
    delete_exchange(ChannelPid, Name, maps:new()).


-spec delete_exchange(Channel :: pid(), Name :: binary(), Params :: map()) ->
    ok | {error, Reason :: term()}.
delete_exchange(ChannelPid, Name, Params) ->
    ExchangeDelete = fox_utils:map_to_exchange_delete(Params),
    ExchangeDelete2 = ExchangeDelete#'exchange.delete'{exchange = Name},
    case fox_utils:channel_call(ChannelPid, ExchangeDelete2) of
        #'exchange.delete_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec bind_exchange(Channel :: pid(),
                    ExchangeSource :: binary(),
                    ExchangeDestination :: binary(),
                    RoutingKey :: binary()) -> ok | {error, Reason :: term()}.
bind_exchange(ChannelPid, Source, Destination, RoutingKey) ->
    bind_exchange(ChannelPid, Source, Destination, RoutingKey, maps:new()).


-spec bind_exchange(Channel :: pid(),
                    ExchangeSource :: binary(),
                    ExchangeDestination :: binary(),
                    RoutingKey :: binary(),
                    Params :: map()) -> ok | {error, Reason :: term()}.
bind_exchange(ChannelPid, Source, Destination, RoutingKey, Params) ->
    ExchangeBind = fox_utils:map_to_exchange_bind(Params),

    ExchangeBind2 = ExchangeBind#'exchange.bind'{
        destination = Destination,
        source = Source,
        routing_key = RoutingKey
    },

    case fox_utils:channel_call(ChannelPid, ExchangeBind2) of
        #'exchange.bind_ok'{} -> ok;
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec declare_queue(Channel :: pid(), Name :: binary()) ->
    ok | #'queue.declare_ok'{} | {error, Reason :: term()}.
declare_queue(ChannelPid, Name) when is_binary(Name) ->
    declare_queue(ChannelPid, Name, maps:new()).


-spec declare_queue(Channel :: pid(), Name :: binary(), Params :: map()) ->
    ok | #'queue.declare_ok'{} | {error, Reason :: term()}.
declare_queue(ChannelPid, Name, Params) ->
    QueueDeclare = fox_utils:map_to_queue_declare(Params),
    QueueDeclare2 = QueueDeclare#'queue.declare'{queue = Name},
    case fox_utils:channel_call(ChannelPid, QueueDeclare2) of
        ok -> ok;
        #'queue.declare_ok'{} = Reply -> Reply;
        {error, Reason} -> {error, Reason}
    end.


-spec delete_queue(Channel :: pid(), Name :: binary()) ->
    #'queue.delete_ok'{} | {error, Reason :: term()}.
delete_queue(ChannelPid, Name) when is_binary(Name) ->
    delete_queue(ChannelPid, Name, maps:new()).


-spec delete_queue(Channel :: pid(), Name :: binary(), Params :: map()) ->
    #'queue.delete_ok'{} | {error, Reason :: term()}.
delete_queue(ChannelPid, Name, Params) ->
    QueueDelete = fox_utils:map_to_queue_delete(Params),
    QueueDelete2 = QueueDelete#'queue.delete'{queue = Name},
    case fox_utils:channel_call(ChannelPid, QueueDelete2) of
        ok -> ok;
        #'queue.delete_ok'{} = Reply -> Reply;
        {error, Reason} -> {error, Reason}
    end.


-spec bind_queue(Channel :: pid(),
                 QueueName :: binary(),
                 ExchangeName :: binary(),
                 RoutingKey :: binary()) -> ok | {error, Reason :: term()}.
bind_queue(ChannelPid, Queue, Exchange, RoutingKey) ->
    bind_queue(ChannelPid, Queue, Exchange, RoutingKey, maps:new()).


-spec bind_queue(Channel :: pid(),
                 QueueName :: binary(),
                 ExchangeName :: binary(),
                 RoutingKey :: binary(),
                 Params :: map()) -> ok | {error, Reason :: term()}.
bind_queue(ChannelPid, Queue, Exchange, RoutingKey, Params) ->
    QueueBind = fox_utils:map_to_queue_bind(Params),
    QueueBind2 = QueueBind#'queue.bind'{queue = Queue,
                                        exchange = Exchange,
                                        routing_key = RoutingKey},
    case fox_utils:channel_call(ChannelPid, QueueBind2) of
        #'queue.bind_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec unbind_queue(Channel :: pid(),
                   QueueName :: binary(),
                   ExchangeName :: binary(),
                   RoutingKey :: binary()) -> ok | {error, Reason :: term()}.
unbind_queue(ChannelPid, Queue, Exchange, RoutingKey) ->
    unbind_queue(ChannelPid, Queue, Exchange, RoutingKey, maps:new()).


-spec unbind_queue(Channel :: pid(),
                   QueueName :: binary(),
                   ExchangeName :: binary(),
                   RoutingKey :: binary(),
                   Params :: map()) -> ok | {error, Reason :: term()}.
unbind_queue(ChannelPid, Queue, Exchange, RoutingKey, Params) ->
    QueueUnbind = fox_utils:map_to_queue_unbind(Params),
    QueueUnbind2 = QueueUnbind#'queue.unbind'{queue = Queue,
                                              exchange = Exchange,
                                              routing_key = RoutingKey},
    case fox_utils:channel_call(ChannelPid, QueueUnbind2) of
        #'queue.unbind_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec publish(PoolOrChannel :: pool_name() | pid(),
              ExchangeName :: binary(),
              RoutingKey :: binary(),
              Payload :: binary()) -> ok | {error, Reason :: term()}.
publish(PoolOrChannel, Exchange, RoutingKey, Payload) ->
    publish(PoolOrChannel, Exchange, RoutingKey, Payload, maps:new()).


-spec publish(PoolOrChannel :: pool_name() | pid(),
              Exchange :: binary(),
              RoutingKey :: binary(),
              Payload :: binary(),
              Params :: map()) -> ok | {error, Reason :: term()}.
publish(Channel, Exchange, RoutingKey, Payload, Params)
    when is_pid(Channel) andalso is_binary(Payload)
    ->
    Publish = fox_utils:map_to_basic_publish(
        Params#{exchange => Exchange, routing_key => RoutingKey}),
    PBasic = fox_utils:map_to_pbasic(Params),
    Message = #amqp_msg{payload = Payload, props = PBasic},

    PublishFun = case Params of
                     #{synchronous := true} -> channel_call;
                     _ -> channel_cast
                 end,
    case fox_utils:PublishFun(Channel, Publish, Message) of
        ok -> ok;
        {error, Reason} -> {error, Reason};
        #'basic.publish'{} -> ok;
        OtherReply -> {error, OtherReply}
    end;

publish(Pool, Exchange, RoutingKey, Payload, Params) ->
    PoolName = fox_utils:name_to_atom(Pool),
    case fox_pub_pool:get_channel(PoolName) of
        {ok, Channel} -> publish(Channel, Exchange, RoutingKey, Payload, Params);
        {error, Reason} -> {error, Reason}
    end.


-spec qos(PoolOrChannel :: pool_name() | pid(),
          Params :: map()) -> ok | {error, Reason :: term()}.
qos(PoolOrChannel, Params) ->
    QoS = fox_utils:map_to_basic_qos(Params),
    if
        is_pid(PoolOrChannel) ->
            #'basic.qos_ok'{} = amqp_channel:call(PoolOrChannel, QoS),
            ok;
        true ->
            PoolName = fox_utils:name_to_atom(PoolOrChannel),
            case fox_pub_pool:get_channel(PoolName) of
                {ok, Channel} -> #'basic.qos_ok'{} = amqp_channel:call(Channel, QoS), ok;
                {error, Reason} -> {error, Reason}
            end
    end.


-spec test_run() -> ok.
test_run() ->
    Formater = #{legacy_header => false, single_line => true},
    Config = #{
               level => info,
               formatter => {logger_formatter, Formater},
               filters => [{hide_progress_info, {fun logger_filters:progress/2, stop}}]
              },
    logger:set_handler_config(default, Config),
    logger:set_primary_config(level, info),

    application:ensure_all_started(fox),

    Params = #{host => "localhost",
               port => 5672,
               virtual_host => <<"/">>,
               username => <<"guest">>,
               password => <<"guest">>},

    ok = validate_params_network(Params),

    create_connection_pool("my_pool", Params, 3),
    {ok, Channel} = get_channel("my_pool"),
    declare_exchange(Channel, <<"my_exchange">>),

    {ok, _Ref1} = subscribe("my_pool", <<"queue_1">>, sample_subs_callback, [<<"queue_1">>, <<"key_1">>]),

    Q = #'basic.consume'{queue = <<"queue_2">>},
    {ok, _Ref2} = subscribe("my_pool", Q, sample_subs_callback, [<<"queue_2">>, <<"key_2">>]),

    timer:sleep(500),

    ok = publish("my_pool", <<"my_exchange">>, <<"key_1">>, <<"Hello 1">>, #{synchronous => true}),
    ok = publish("my_pool", <<"my_exchange">>, <<"key_2">>, <<"Hello 2">>),

    %% timer:sleep(2000),
    %% unsubscribe("my_pool", _Ref2),
    ok.
