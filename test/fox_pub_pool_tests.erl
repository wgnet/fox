-module(fox_pub_pool_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").


setup() ->
    application:ensure_all_started(fox),
    fox_utils:map_to_params_network(#{host => "localhost",
        port => 5672,
        virtual_host => <<"/">>,
        username => <<"guest">>,
        password => <<"guest">>}).


get_channel_test() ->
    Params = setup(),

    {ok, Pid} = fox_pub_pool:start_link(pool_1, Params),
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),
    ?assertMatch(Pid, whereis('fox_pub_pool/pool_1')),

    {ok, C1} = fox_pub_pool:get_channel(pool_1),
    ?assert(erlang:is_process_alive(C1)),
    {ok, C2} = fox_pub_pool:get_channel(pool_1),
    ?assert(erlang:is_process_alive(C2)),
    {ok, C3} = fox_pub_pool:get_channel(pool_1),
    ?assert(erlang:is_process_alive(C3)),

    ?assertNotEqual(C1, C2),
    ?assertNotEqual(C2, C3),
    ?assertNotEqual(C1, C3),

    fox_pub_pool:stop(pool_1),
    ?assertNot(erlang:is_process_alive(Pid)),
    ?assertNot(erlang:is_process_alive(C1)),
    ?assertNot(erlang:is_process_alive(C2)),
    ?assertNot(erlang:is_process_alive(C3)),
    ok.


reconnect_test() ->
    Params = setup(),
    {ok, Pid} = fox_pub_pool:start_link(pool_2, Params),
    timer:sleep(200),

    [state, Conn | _] = tuple_to_list(sys:get_state(Pid)),
    ?assert(is_pid(Conn)),

    ok = amqp_connection:close(Conn),
    timer:sleep(200),

    [state, Conn2 | _] = tuple_to_list(sys:get_state(Pid)),
    ?assert(is_pid(Conn2)),
    ?assertNotEqual(Conn, Conn2),

    ok = fox_pub_pool:stop(pool_2),
    ?assertNot(erlang:is_process_alive(Pid)),
    ?assertNot(erlang:is_process_alive(Conn)),
    ?assertNot(erlang:is_process_alive(Conn2)),

    ok.