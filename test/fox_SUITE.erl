-module(fox_SUITE).

%% test needs connection to RabbitMQ

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").


-export([all/0,
         init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2,
         create_channel_test/1, subscribe_test/1, subscribe_state_test/1
        ]).


-spec all() -> list().
all() ->
    [create_channel_test,
     subscribe_test,
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
    Config.


-spec end_per_testcase(atom(), list()) -> list().
end_per_testcase(Test, Config) ->
    ok = fox:close_connection_pool(Test),
    Config.


-spec create_channel_test(list()) -> ok.
create_channel_test(_Config) ->
    {ok, Channel} = fox:create_channel(create_channel_test),
    ?assertEqual(ok, fox:declare_exchange(Channel, <<"my_exchange">>)),
    ?assertEqual(ok, fox:delete_exchange(Channel, <<"my_exchange">>)),
    amqp_channel:close(Channel),
    ok.


-spec subscribe_test(list()) -> ok.
subscribe_test(_Config) ->
    T = ets:new(subscribe_test_ets, [public, named_table]),
    SortF = fun(I1, I2) -> element(1, I1) < element(1, I2) end,

    {ok, SChannel} = fox:subscribe(subscribe_test, subscribe_test, [1,2,3]),

    timer:sleep(200),
    Res1 = lists:sort(SortF, ets:tab2list(T)),
    ct:pal("Res1: ~p", [Res1]),
    ?assertMatch([{0, init, SChannel, [1,2,3]}], Res1),

    {ok, PChannel} = fox:create_channel(subscribe_test),
    fox:publish(PChannel, <<"my_exchange">>, <<"my_key">>, <<"Hi there!">>),
    timer:sleep(200),
    Res2 = lists:sort(SortF, ets:tab2list(T)),
    ct:pal("Res2: ~p", [Res2]),
    ?assertMatch([
                  {0, init, SChannel, [1,2,3]},
                  {1, handle_basic_deliver, SChannel, <<"Hi there!">>}
                 ],
                 Res2),

    fox:publish(PChannel, <<"my_exchange">>, <<"my_key">>, <<"Hello!">>),
    timer:sleep(200),
    Res3 = lists:sort(SortF, ets:tab2list(T)),
    ct:pal("Res3: ~p", [Res3]),
    ?assertMatch([
                  {0, init, SChannel, [1,2,3]},
                  {1, handle_basic_deliver, SChannel, <<"Hi there!">>},
                  {2, handle_basic_deliver, SChannel, <<"Hello!">>}
                 ],
                 Res3),

    fox:unsubscribe(subscribe_test, SChannel),
    timer:sleep(200),
    Res4 = lists:sort(SortF, ets:tab2list(T)),
    ct:pal("Res4: ~p", [Res4]),
    ?assertMatch([
                  {0, init, SChannel, [1,2,3]},
                  {1, handle_basic_deliver, SChannel, <<"Hi there!">>},
                  {2, handle_basic_deliver, SChannel, <<"Hello!">>},
                  {3, terminate, SChannel}
                 ],
                 Res4),

    amqp_channel:close(PChannel),
    ok.


-spec subscribe_state_test(list()) -> ok.
subscribe_state_test(_Config) ->
    {ok, ChannelPid} = fox:subscribe(subscribe_state_test, sample_channel_consumer),
    ?assert(erlang:is_process_alive(ChannelPid)),

    ConnectionSups = supervisor:which_children(fox_connection_pool_sup),
    ct:pal("ConnectionSups: ~p", [ConnectionSups]),
    ConnectionSupPid = lists:foldl(fun({{fox_connection_sup, subscribe_state_test}, SupPid, _, _}, _Acc) -> SupPid;
                                      (_, Acc) -> Acc
                                   end, undefined, ConnectionSups),
    ct:pal("ConnectionSupPid: ~p", [ConnectionSupPid]),

    ConnectionWorkers = supervisor:which_children(ConnectionSupPid),
    ct:pal("ConnectionWorkers: ~p", [ConnectionWorkers]),
    {_, ConnectionWorkerPid, _, _} = hd(lists:reverse(ConnectionWorkers)),
    ct:pal("ConnectionWorkerPid: ~p", [ConnectionWorkerPid]),

    State = sys:get_state(ConnectionWorkerPid),
    ct:pal("State: ~p", [State]),
    {state, _, _, _, Consumers, _, TID} = State,

    EtsData = lists:sort(ets:tab2list(TID)),
    ct:pal("EtsData: ~p", [EtsData]),
    ?assertMatch([{ChannelPid, {consumer, _, _}, {channel, ChannelPid, _}},
                  {_, {consumer, _, _}, {channel, ChannelPid, _}}
                 ],
                 EtsData),


    [{ChannelPid, {consumer, ConsumerPid, _}, _}] = ets:lookup(TID, ChannelPid),
    ?assertEqual({ok, {ConsumerPid, sample_channel_consumer, []}}, maps:find(ChannelPid, Consumers)),

    %% Unsubscribe
    fox:unsubscribe(subscribe_state_test, ChannelPid),

    timer:sleep(200),
    ?assert(not erlang:is_process_alive(ChannelPid)),

    State2 = sys:get_state(ConnectionWorkerPid),
    {state, _, _, _, Consumers2, _, TID} = State2,

    ?assertEqual(error, maps:find(ChannelPid, Consumers2)),
    ?assertEqual([], ets:tab2list(TID)),
    ok.
