-module(fox_SUITE).

%% test needs connection to RabbitMQ

-include("fox.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile([export_all]).

-spec all() -> list().
all() ->
    [create_channel_test
    ,publish_test
    ,sync_publish_test
    ,subscribe_test
    ,subscribe_state_test
    ].


-spec init_per_suite(list()) -> list().
init_per_suite(Config) ->
    application:ensure_all_started(fox),
    application:set_env(fox, publish_pool_size, 4),
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
    Config.


-spec end_per_testcase(atom(), list()) -> list().
end_per_testcase(Test, Config) ->
    ok = fox:close_connection_pool(Test),
    Config.


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

    timer:sleep(200),
    ok = fox:publish(publish_test, <<"my_exchange">>, <<"my_queue">>, <<"Hello">>),
    ok.


-spec sync_publish_test(list()) -> ok.
sync_publish_test(_Config) ->
    timer:sleep(200),
    ok = fox:publish(sync_publish_test, <<"my_exchange">>, <<"my_queue">>, <<"Hello">>, #{synchronous => true}),
    ok.


-spec subscribe_test(list()) -> ok.
subscribe_test(_Config) ->
    T = ets:new(subscribe_test_ets, [public, named_table]),
    SortF = fun(I1, I2) -> element(1, I1) < element(1, I2) end,

    {ok, Ref} = fox:subscribe(subscribe_test, <<"my_queue">>, subscribe_test, "some args"),

    timer:sleep(200),
    Res1 = lists:sort(SortF, ets:tab2list(T)),
    ct:log("Res1: ~p", [Res1]),
    ?assertMatch([{1, init, "some args"}], Res1),

    fox:publish(subscribe_test, <<"my_exchange">>, <<"my_key">>, <<"Hi there!">>),
    timer:sleep(200),
    Res2 = lists:sort(SortF, ets:tab2list(T)),
    ct:log("Res2: ~p", [Res2]),
    ?assertMatch([
                  {1, init, "some args"},
                  {2, handle_basic_deliver, <<"Hi there!">>}
                 ],
                 Res2),

    fox:publish(subscribe_test, <<"my_exchange">>, <<"my_key">>, <<"Hello!">>),
    timer:sleep(200),
    Res3 = lists:sort(SortF, ets:tab2list(T)),
    ct:log("Res3: ~p", [Res3]),
    ?assertMatch([
                  {1, init, "some args"},
                  {2, handle_basic_deliver, <<"Hi there!">>},
                  {3, handle_basic_deliver, <<"Hello!">>}
                 ],
                 Res3),

    fox:unsubscribe(subscribe_test, Ref),
    timer:sleep(200),
    Res4 = lists:sort(SortF, ets:tab2list(T)),
    ct:log("Res4: ~p", [Res4]),
    ?assertMatch([
                  {1, init, "some args"},
                  {2, handle_basic_deliver, <<"Hi there!">>},
                  {3, handle_basic_deliver, <<"Hello!">>},
                  {4, terminate}
                 ],
                 Res4),

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
    Subscribers = hd(lists:reverse(tuple_to_list(ConnState))),
    ?assertEqual([SubsPid], Subscribers),

    SubsState = sys:get_state(SubsPid),
    ct:log("SubsState: ~p", [SubsState]),
    ?assertMatch(#subscription{
        queue = Q,
        subs_module = sample_subs_callback,
        subs_args = [<<"q">>, <<"rk">>],
        subs_state = {<<"my_exchange">>, <<"q">>, <<"rk">>}
    }, SubsState),

    fox:unsubscribe(subscribe_state_test, Ref),
    ok.
