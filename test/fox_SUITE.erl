-module(fox_SUITE).

%% test needs connection to RabbitMQ

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").


-export([all/0,
         init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2,
         create_channel_test/1, subscribe_test/1
        ]).


-spec all() -> list().
all() ->
    [create_channel_test,
     subscribe_test
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
