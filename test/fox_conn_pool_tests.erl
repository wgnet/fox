-module(fox_conn_pool_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").


setup() ->
    application:ensure_all_started(fox),
    fox_utils:map_to_params_network(#{host => "localhost",
        port => 5672,
        virtual_host => <<"/">>,
        username => <<"guest">>,
        password => <<"guest">>}).


get_conn_worker_test() ->
    Params = setup(),
    {ok, SupPid} = fox_conn_sup:start_link(pool_1),
    {ok, Pid} = fox_conn_pool:start_link(pool_1, Params, 3),
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),
    ?assertMatch(Pid, whereis('fox_conn_pool/pool_1')),

    W1 = fox_conn_pool:get_conn_worker(pool_1),
    W2 = fox_conn_pool:get_conn_worker(pool_1),
    W3 = fox_conn_pool:get_conn_worker(pool_1),
    W4 = fox_conn_pool:get_conn_worker(pool_1),
    ?assertNotEqual(W1, W2),
    ?assertNotEqual(W1, W3),
    ?assertNotEqual(W2, W3),
    ?assertEqual(W1, W4),

    fox_conn_pool:stop(pool_1),
    ?assertNot(erlang:is_process_alive(Pid)),
    ?assertNot(erlang:is_process_alive(W1)),
    ?assertNot(erlang:is_process_alive(W2)),
    ?assertNot(erlang:is_process_alive(W3)),

    exit(SupPid, normal),
    ok.


subs_meta_test() ->
    Params = setup(),
    {ok, SupPid} = fox_conn_sup:start_link(pool_2),
    {ok, _Pid} = fox_conn_pool:start_link(pool_2, Params, 1),

    Ref1 = make_ref(),
    SM1 = #subs_meta{ref = Ref1},
    Ref2 = make_ref(),
    SM2 = #subs_meta{ref = Ref2},
    ?assertEqual(not_found, fox_conn_pool:get_subs_meta(pool_2, Ref1)),
    ?assertEqual(not_found, fox_conn_pool:get_subs_meta(pool_2, Ref2)),

    fox_conn_pool:save_subs_meta(pool_2, SM1),
    fox_conn_pool:save_subs_meta(pool_2, SM2),
    ?assertEqual(SM1, fox_conn_pool:get_subs_meta(pool_2, Ref1)),
    ?assertEqual(SM2, fox_conn_pool:get_subs_meta(pool_2, Ref2)),

    fox_conn_pool:remove_subs_meta(pool_2, Ref1),
    ?assertEqual(not_found, fox_conn_pool:get_subs_meta(pool_2, Ref1)),
    ?assertEqual(SM2, fox_conn_pool:get_subs_meta(pool_2, Ref2)),

    fox_conn_pool:remove_subs_meta(pool_2, Ref2),
    ?assertEqual(not_found, fox_conn_pool:get_subs_meta(pool_2, Ref1)),
    ?assertEqual(not_found, fox_conn_pool:get_subs_meta(pool_2, Ref2)),

    fox_conn_pool:stop(pool_2),
    exit(SupPid, normal),
    ok.