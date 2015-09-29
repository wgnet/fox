-module(fox).

-export([validate_params_network/1,
         create_connection_pool/2,
         close_connection_pool/1,
         create_channel/1,
         subscribe/2, subscribe/3, unsubscribe/2,
         declare_exchange/2,
         test_run/0]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


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


-spec create_connection_pool(connection_name(), #amqp_params_network{} | map()) -> ok.
create_connection_pool(ConnectionName, Params) when is_map(Params) ->
    create_connection_pool(ConnectionName, fox_utils:map_to_params_network(Params));

create_connection_pool(ConnectionName, Params) ->
    true = fox_utils:validate_params_network_types(Params),
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    {ok, PoolSize} = application:get_env(fox, connection_pool_size),
    fox_connection_pool_sup:start_pool(ConnectionName2, Params, PoolSize),
    ok.


-spec close_connection_pool(connection_name()) -> ok | {error, term()}.
close_connection_pool(ConnectionName) ->
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    fox_connection_pool_sup:stop_pool(ConnectionName2).


-spec create_channel(connection_name()) -> {ok, pid()} | {error, term()}.
create_channel(ConnectionName) ->
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    fox_connection_pool_sup:create_channel(ConnectionName2).


-spec subscribe(connection_name(), module()) -> {ok, pid()} | {error, term()}.
subscribe(ConnectionName, ConsumerModule) ->
    subscribe(ConnectionName, ConsumerModule, []).


-spec subscribe(connection_name(), module(), list()) -> {ok, pid()} | {error, term()}.
subscribe(ConnectionName, ConsumerModule, ConsumerModuleArgs) ->
    true = fox_utils:validate_consumer_behaviour(ConsumerModule),
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    fox_connection_pool_sup:subscribe(ConnectionName2, ConsumerModule, ConsumerModuleArgs).


-spec unsubscribe(connection_name(), pid()) -> ok | {error, term()}.
unsubscribe(ConnectionName, ChannelPid) ->
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    fox_connection_pool_sup:unsubscribe(ConnectionName2, ChannelPid).


-spec declare_exchange(pid(), binary()) -> ok | {error, term()}.
declare_exchange(ChannelPid, Name) when is_binary(Name) ->
    declare_exchange(ChannelPid, Name, maps:new()).


-spec declare_exchange(pid(), binary(), map()) -> ok | {error, term()}.
declare_exchange(ChannelPid, Name, Params) ->
    ExchangeDeclare = fox_utils:map_to_exchange_declare(Params),
    ExchangeDeclare2 = ExchangeDeclare#'exchange.declare'{exchange = Name},
    case amqp_channel:call(ChannelPid, ExchangeDeclare2) of
        #'exchange.declare_ok'{} -> ok;
        {error, Reason} -> {error, Reason}
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
    {ok, SChannel} = subscribe("test_pool", sample_channel_consumer),
    {ok, PChannel} = create_channel("test_pool"),

    Publish = #'basic.publish'{exchange = <<"my_exchange">>, routing_key = <<"my_key">>},
    Message = #amqp_msg{payload = <<"Hello there!">>},
    amqp_channel:cast(PChannel, Publish, Message),

    unsubscribe("test_pool", SChannel),
    %% close_connection_pool("test_pool"),

    amqp_channel:close(PChannel),
    ok.
