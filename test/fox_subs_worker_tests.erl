-module(fox_subs_worker_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").


setup() ->
    application:ensure_all_started(fox),
    fox_utils:map_to_params_network(#{host => "localhost",
        port => 5672,
        virtual_host => <<"/">>,
        username => <<"guest">>,
        password => <<"guest">>}).


start_stop_test() ->
    Params = setup(),
    fox:create_connection_pool(fox_subs_worker_start_stop_test, Params, 3),

    S = #subscription{
        pool_name = fox_subs_worker_start_stop_test,
        basic_consume = #'basic.consume'{queue = <<"q1">>},
        subs_module = sample_subs_callback,
        subs_args = [<<"q1">>, <<"k1">>]
    },
    {ok, Pid} = fox_subs_worker:start_link(S),
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),


    fox_subs_worker:stop(Pid),
    ?assertNot(erlang:is_process_alive(Pid)),
    ok.


connection_established_test() ->
    Params = setup(),
    fox:create_connection_pool(fox_subs_worker_connection_established_test, Params, 3),
    {ok, Conn} = amqp_connection:start(Params),

    S = #subscription{
        pool_name = fox_subs_worker_connection_established_test,
        basic_consume = #'basic.consume'{queue = <<"q1">>},
        subs_module = sample_subs_callback,
        subs_args = [<<"q1">>, <<"k1">>]
    },
    {ok, Pid} = fox_subs_worker:start_link(S),
    fox_subs_worker:connection_established(Pid, Conn),

    timer:sleep(200),
    fox_subs_worker:stop(Pid),
    ok.
