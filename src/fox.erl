-module(fox).

-export([create_connection_pool/2]).
-export([test_run/0]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


%%% module API

-spec create_connection_pool(connection_name(), #amqp_params_network{} | map()) -> ok.
create_connection_pool(ConnectionName, Params) when is_map(Params) ->
    Params2 = #amqp_params_network{
                host = maps:get(host, Params),
                port = maps:get(port, Params),
                virtual_host = maps:get(virtual_host, Params),
                username = maps:get(username, Params),
                password = maps:get(password, Params),
                heartbeat = maps:get(heartbeat, Params, 10),
                connection_timeout = maps:get(connection_timeout, Params, 10)
               },
    create_connection_pool(ConnectionName, Params2);

create_connection_pool(ConnectionName, Params) ->
    %% TODO validate params types
    ConnectionName2 = fox_utils:name_to_atom(ConnectionName),
    {ok, PoolSize} = application:get_env(fox, connection_pool_size),
    fox_connection_pool_sup:start_pool(ConnectionName2, Params, PoolSize),
    ok.


-spec(test_run() -> ok).
test_run() ->
    application:ensure_all_started(fox),
    Params1 = #{host => "localhost",
                port => 5672,
                virtual_host => <<"/">>,
                username => <<"guest">>,
                password => <<"guest">>},
    create_connection_pool("test_pool", Params1),
    Params2 = #{host => "localhost",
                port => 5672,
                virtual_host => <<"/test">>,
                username => <<"guest">>,
                password => <<"guest">>},
    create_connection_pool("pool_2", Params2),
    ok.
