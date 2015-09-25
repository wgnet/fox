-module(fox).

-export([validate_params_network/1,
         create_connection_pool/2,
         close_connection_pool/1,
         create_channel/1, create_channel/3,
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


-spec create_channel(connection_name(), module(), list()) -> {ok, pid()} | {error, term()}.
create_channel(ConnectionName, ConsumerModule, ConsumerModuleArgs) ->
    true = fox_utils:validate_consumer_behaviour(ConsumerModule),
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    fox_connection_pool_sup:create_channel(ConnectionName2, ConsumerModule, ConsumerModuleArgs).


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

    %% create_connection_pool("pool_2", Params#{virtual_host => <<"/test">>}),
    %% timer:sleep(1000),
    %% ok = close_connection_pool("pool_2"),

    Channel1 = create_channel("test_pool", fox_sample_consumer, ["sc 1", 1]),
    ?d("Channel1: ~p", [Channel1]),
    Channel2 = create_channel("test_pool", fox_sample_consumer, ["sc 2", 2]),
    ?d("Channel2: ~p", [Channel2]),
    ok.
