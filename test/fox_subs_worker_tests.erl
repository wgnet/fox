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
    PoolName = fox_subs_worker_start_stop_test,
    Params = setup(),
    fox:create_connection_pool(PoolName, Params, 3),

    SubsRef = make_ref(),
    S = #subscription{
           ref = SubsRef,
           pool_name = fox_subs_worker_start_stop_test,
           basic_consume = #'basic.consume'{queue = <<"q1">>},
           subs_module = sample_subs_callback,
           subs_args = [<<"q1">>, <<"k1">>]
          },
    {ok, Pid} = fox_subs_worker:start_link(S, []),
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),

    ?assertMatch(
       #subs_meta{ref = SubsRef, subs_worker = Pid},
       fox_conn_pool:get_subs_meta(PoolName, SubsRef)
      ),

    fox_subs_worker:stop(Pid),
    ?assertNot(erlang:is_process_alive(Pid)),
    ok.


connection_established_test() ->
    PoolName = fox_subs_worker_connection_established_test,
    Params = setup(),
    fox:create_connection_pool(PoolName, Params, 3),
    {ok, Conn} = amqp_connection:start(Params),

    S = #subscription{
        pool_name = PoolName,
        basic_consume = #'basic.consume'{queue = <<"q1">>},
        subs_module = sample_subs_callback,
        subs_args = [<<"q1">>, <<"k1">>]
    },
    {ok, Pid} = fox_subs_worker:start_link(S, []),
    fox_subs_worker:connection_established(Pid, Conn),

    timer:sleep(200),
    #subscription{channel = Channel} = sys:get_state(Pid),
    ?assert(erlang:is_process_alive(Channel)),

    fox_subs_worker:stop(Pid),
    ok.
