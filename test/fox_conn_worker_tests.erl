-module(fox_conn_worker_tests).

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
    {ok, Pid} = fox_conn_worker:start_link(some_pool, 1, Params),

    ?assertMatch({status, _}, erlang:process_info(Pid, status)),
    ?assertMatch(Pid, whereis('fox_conn_worker/some_pool/1')),

    ok = fox_conn_worker:stop(Pid),
    ?assertEqual(undefined, erlang:process_info(Pid, status)),

    ok.


reconnect_test() ->
    Params = setup(),
    {ok, Pid} = fox_conn_worker:start_link(some_pool, 1, Params),
    timer:sleep(200),

    #conn_worker_state{connection = Conn} = sys:get_state(Pid),
    ?assert(is_pid(Conn)),

    ok = amqp_connection:close(Conn),
    timer:sleep(200),

    #conn_worker_state{connection = Conn2} = sys:get_state(Pid),
    ?assert(is_pid(Conn2)),
    ?assertNotEqual(Conn, Conn2),

    ok = fox_conn_worker:stop(Pid),
    ?assertEqual(undefined, erlang:process_info(Pid, status)),

    ok.

register_subscriber_test() ->
    Params = setup(),
    {ok, Pid} = fox_conn_worker:start_link(some_pool, 1, Params),
    SPid = self(),

    fox_conn_worker:register_subscriber(Pid, SPid),    
    timer:sleep(100),

    #conn_worker_state{subscribers = Subs} = sys:get_state(Pid),
    ?assertMatch([{SPid, _}], Subs),

    receive
        {'$gen_cast', {connection_established, _}} -> ok
    after 500 ->
        throw(dont_get_connection_established)
    end,
    
    fox_conn_worker:remove_subscriber(Pid, SPid),
    timer:sleep(100),

    #conn_worker_state{subscribers = Subs2} = sys:get_state(Pid),
    ?assertEqual([], Subs2),

    ok.
    
    
