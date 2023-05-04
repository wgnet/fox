-module(fox_SUITE).

%% test needs connection to RabbitMQ

-include("fox.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(nowarn_export_all).
-compile([export_all]).

-define(DELAY, 500).

-spec all() -> list().
all() ->
    [
        start_stop_pool_test,
        create_channel_test,
        publish_test,
        sync_publish_test,
        subscribe_test,
        subscribe_2_queues_test,
        subscribe_state_test
    ].


-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    application:ensure_all_started(fox),
    Config.


-spec end_per_suite(list()) -> list().
end_per_suite(Config) ->
    application:stop(fox),
    Config.


-spec init_per_testcase(atom(), list()) -> list().
init_per_testcase(Test, Config) ->
    Params = #{host => "localhost",
               port => 5672,
               virtual_host => <<"/">>,
               username => <<"guest">>,
               password => <<"guest">>},
    ok = fox:create_connection_pool(Test, Params),
    [{params, Params} | Config].


-spec end_per_testcase(atom(), list()) -> list().
end_per_testcase(Test, Config) ->
    ok = fox:close_connection_pool(Test),
    Config.


-spec start_stop_pool_test(list()) -> ok.
start_stop_pool_test(Config) ->
    PoolSup = erlang:whereis('fox_conn_pool_sup/start_stop_pool_test'),
    ?assert(erlang:is_process_alive(PoolSup)),
    ConnPool = erlang:whereis('fox_conn_pool/start_stop_pool_test'),
    ?assert(erlang:is_process_alive(ConnPool)),
    ConnSup = erlang:whereis('fox_conn_sup/start_stop_pool_test'),
    ?assert(erlang:is_process_alive(ConnSup)),
    PubPool = erlang:whereis('fox_pub_pool/start_stop_pool_test'),
    ?assert(erlang:is_process_alive(PubPool)),
    SubsSup = erlang:whereis('fox_subs_sup/start_stop_pool_test'),
    ?assert(erlang:is_process_alive(SubsSup)),
    W1 = erlang:whereis('fox_conn_worker/start_stop_pool_test/1'),
    ?assert(erlang:is_process_alive(W1)),
    W2 = erlang:whereis('fox_conn_worker/start_stop_pool_test/2'),
    ?assert(erlang:is_process_alive(W2)),
    W3 = erlang:whereis('fox_conn_worker/start_stop_pool_test/3'),
    ?assert(erlang:is_process_alive(W3)),
    W4 = erlang:whereis('fox_conn_worker/start_stop_pool_test/4'),
    ?assert(erlang:is_process_alive(W4)),
    ?assertEqual(undefined, erlang:whereis('fox_conn_worker/start_stop_pool_test/5')),

    Params = ?config(params, Config),
    ok = fox:create_connection_pool(my_cool_pool, Params, 3),
    PoolSup2 = erlang:whereis('fox_conn_pool_sup/my_cool_pool'),
    ?assert(erlang:is_process_alive(PoolSup2)),
    ConnPool2 = erlang:whereis('fox_conn_pool/my_cool_pool'),
    ?assert(erlang:is_process_alive(ConnPool2)),
    ConnSup2 = erlang:whereis('fox_conn_sup/my_cool_pool'),
    ?assert(erlang:is_process_alive(ConnSup2)),
    PubPool2 = erlang:whereis('fox_pub_pool/my_cool_pool'),
    ?assert(erlang:is_process_alive(PubPool2)),
    SubsSup2 = erlang:whereis('fox_subs_sup/my_cool_pool'),
    ?assert(erlang:is_process_alive(SubsSup2)),
    W21 = erlang:whereis('fox_conn_worker/my_cool_pool/1'),
    ?assert(erlang:is_process_alive(W21)),
    W22 = erlang:whereis('fox_conn_worker/my_cool_pool/2'),
    ?assert(erlang:is_process_alive(W22)),
    ?assertEqual(undefined, erlang:whereis('fox_conn_worker/my_cool_pool/3')),

    ok = fox:close_connection_pool(my_cool_pool),
    ?assertNot(erlang:is_process_alive(PoolSup2)),
    ?assertNot(erlang:is_process_alive(ConnPool2)),
    ?assertNot(erlang:is_process_alive(ConnSup2)),
    ?assertNot(erlang:is_process_alive(PubPool2)),
    ?assertNot(erlang:is_process_alive(SubsSup2)),
    ?assertNot(erlang:is_process_alive(W21)),
    ?assertNot(erlang:is_process_alive(W22)),
    ok.


-spec create_channel_test(list()) -> ok.
create_channel_test(_Config) ->
    {ok, Channel} = fox:get_channel(create_channel_test),
    ?assertEqual(ok, fox:declare_exchange(Channel, <<"my_exchange">>)),
    ?assertEqual(ok, fox:delete_exchange(Channel, <<"my_exchange">>)),
    amqp_channel:close(Channel),
    ok.


-spec publish_test(list()) -> ok.
publish_test(_Config) ->
    Res = fox:publish(publish_test, <<"my_exchange">>, <<"my_queue">>, <<"Hello">>),
    true = (Res == ok orelse Res == {error, no_connection}),

    timer:sleep(?DELAY),
    ok = fox:publish(publish_test, <<"my_exchange">>, <<"my_queue">>, <<"Hello">>),
    ok.


-spec sync_publish_test(list()) -> ok.
sync_publish_test(_Config) ->
    timer:sleep(?DELAY),
    ok = fox:publish(sync_publish_test, <<"my_exchange">>, <<"my_queue">>, <<"Hello">>, #{synchronous => true}),
    ok.


-spec subscribe_test(list()) -> ok.
subscribe_test(_Config) ->
    T = ets:new(subscribe_test_ets, [public, named_table]),
    E = <<"my_exchange">>,
    Q = <<"my_queue">>,
    RK = <<"my_key">>,
    Args = {T, E, Q, RK},
    {ok, Ref} = fox:subscribe(subscribe_test, Q, subs_test_callback, Args),

    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([{1, Q, init, Args}], get_subs_log(T)),

    fox:publish(subscribe_test, E, RK, <<"Hi there!">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q, init, Args},
        {2, Q, handle_basic_deliver, <<"Hi there!">>}
    ], get_subs_log(T)),

    fox:publish(subscribe_test, E, RK, <<"Hello!">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q, init, Args},
        {2, Q, handle_basic_deliver, <<"Hi there!">>},
        {3, Q, handle_basic_deliver, <<"Hello!">>}
    ], get_subs_log(T)),

    fox:unsubscribe(subscribe_test, Ref),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q, init, Args},
        {2, Q, handle_basic_deliver, <<"Hi there!">>},
        {3, Q, handle_basic_deliver, <<"Hello!">>},
        {4, Q, terminate}
    ], get_subs_log(T)),

    ets:delete(T),
    ok.


-spec subscribe_2_queues_test(list()) -> ok.
subscribe_2_queues_test(_Config) ->
    Pool = subscribe_2_queues_test,
    T = ets:new(subscribe_2_queues_test_ets, [public, named_table]),
    E = <<"my_exchange">>,
    Q1 = <<"q1">>,
    K1 = <<"k1">>,
    Args1 = {T, E, Q1, K1},
    {ok, Ref1} = fox:subscribe(Pool, Q1, subs_test_callback, Args1),

    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1}
    ], get_subs_log(T)),

    Q2 = <<"q2">>,
    K2 = <<"k2">>,
    Args2 = {T, E, Q2, K2},
    {ok, Ref2} = fox:subscribe(Pool, Q2, subs_test_callback, Args2),

    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2}
    ], get_subs_log(T)),

    fox:publish(Pool, E, K1, <<"Msg1 to K1">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>}
    ], get_subs_log(T)),

    fox:publish(Pool, E, K2, <<"Msg2 to K2">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>},
        {4, Q2, handle_basic_deliver, <<"Msg2 to K2">>}
    ], get_subs_log(T)),

    fox:publish(Pool, E, K2, <<"Msg3 to K2">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>},
        {4, Q2, handle_basic_deliver, <<"Msg2 to K2">>},
        {5, Q2, handle_basic_deliver, <<"Msg3 to K2">>}
    ], get_subs_log(T)),

    fox:publish(Pool, E, K1, <<"Msg4 to K1">>),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>},
        {4, Q2, handle_basic_deliver, <<"Msg2 to K2">>},
        {5, Q2, handle_basic_deliver, <<"Msg3 to K2">>},
        {6, Q1, handle_basic_deliver, <<"Msg4 to K1">>}
    ], get_subs_log(T)),


    fox:unsubscribe(Pool, Ref1),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>},
        {4, Q2, handle_basic_deliver, <<"Msg2 to K2">>},
        {5, Q2, handle_basic_deliver, <<"Msg3 to K2">>},
        {6, Q1, handle_basic_deliver, <<"Msg4 to K1">>},
        {7, Q1, terminate}
    ], get_subs_log(T)),

    fox:unsubscribe(Pool, Ref2),
    timer:sleep(?DELAY),
    ct:log("~p", [get_subs_log(T)]),
    ?assertMatch([
        {1, Q1, init, Args1},
        {2, Q2, init, Args2},
        {3, Q1, handle_basic_deliver, <<"Msg1 to K1">>},
        {4, Q2, handle_basic_deliver, <<"Msg2 to K2">>},
        {5, Q2, handle_basic_deliver, <<"Msg3 to K2">>},
        {6, Q1, handle_basic_deliver, <<"Msg4 to K1">>},
        {7, Q1, terminate},
        {8, Q2, terminate}
    ], get_subs_log(T)),

    ets:delete(T),
    ok.


-spec subscribe_state_test(list()) -> ok.
subscribe_state_test(_Config) ->
    Q = #'basic.consume'{queue = <<"q">>},
    {ok, Ref} = fox:subscribe(subscribe_state_test, Q, sample_subs_callback, [<<"q">>, <<"rk">>]),

    #subs_meta{conn_worker = ConnPid, subs_worker = SubsPid} =
        fox_conn_pool:get_subs_meta(subscribe_state_test, Ref),

    ConnState = sys:get_state(ConnPid),
    ct:log("ConnState: ~p", [ConnState]),
    #conn_worker_state{subscribers = Subscribers} = ConnState,
    ?assertEqual([SubsPid], Subscribers),

    SubsState = sys:get_state(SubsPid),
    ct:log("SubsState: ~p", [SubsState]),
    ?assertMatch(#subscription{
        basic_consume = Q,
        subs_module = sample_subs_callback,
        subs_args = [<<"q">>, <<"rk">>],
        subs_state = {<<"my_exchange">>, <<"q">>, <<"rk">>}
    }, SubsState),

    fox:unsubscribe(subscribe_state_test, Ref),
    ok.


-spec get_subs_log(ets:tab()) -> [tuple()].
get_subs_log(Ets) ->
    lists:sort(
        fun(I1, I2) -> element(1, I1) < element(1, I2) end,
        ets:tab2list(Ets)).
