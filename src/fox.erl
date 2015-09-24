-module(fox).

-export([test_run/0]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


%%% module API

-spec(test_run() -> ok).
test_run() ->
    application:ensure_all_started(fox),
    Params = #amqp_params_network{
                host = "localhost",
                port = 5672,
                virtual_host = "/",
                username = "guest",
                password = "guest",
                heartbeat = 10,
                connection_timeout = 10
               },
    {ok, PoolSize} = application:get_env(fox, connection_pool_size),
    fox_connection_pool_sup:start_pool(Params, PoolSize),
    ok.
