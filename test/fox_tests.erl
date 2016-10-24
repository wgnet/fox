-module(fox_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").

setup() ->
    application:ensure_all_started(fox),
    fox_utils:map_to_params_network(#{host => "localhost",
                                      port => 5672,
                                      virtual_host => <<"/">>,
                                      username => <<"guest">>,
                                      password => <<"guest">>}).


validate_params_network_test() ->
    Params = setup(),
    ?assertEqual(ok, fox:validate_params_network(Params)),
    ?assertMatch({error, _}, fox:validate_params_network(Params#'amqp_params_network'{password = <<"gG5Z2pVwK4">>})),
    ?assertThrow({invalid_amqp_params_network, "host should be string"},
                 fox:validate_params_network(Params#'amqp_params_network'{host = <<"localhost">>})),
    ?assertThrow({invalid_amqp_params_network, "username should be binary"},
                 fox:validate_params_network(Params#'amqp_params_network'{username = "guest"})),
    ok.


create_channel_test() ->
    Params = setup(),
    fox:create_connection_pool("pool_1", Params),
    {ok, Channel} = fox:get_channel("pool_1"),
    ?assertMatch({status, _}, erlang:process_info(Channel, status)),
    ?assertEqual(ok, amqp_channel:close(Channel)),
    fox:close_connection_pool("pool_1"),
    ok.


declare_exchange_test() ->
    Params = setup(),
    fox:create_connection_pool("pool_2", Params),
    {ok, Channel} = fox:get_channel("pool_2"),
    ?assertEqual(ok, fox:declare_exchange(Channel, <<"my_exchange">>)),
    ?assertEqual(ok, fox:declare_exchange(Channel, <<"other_exchange">>, #{nowait => true})),
    ?assertEqual(ok, fox:delete_exchange(Channel, <<"my_exchange">>)),
    ?assertEqual(ok, fox:delete_exchange(Channel, <<"other_exchange">>)),
    ?assertEqual(ok, amqp_channel:close(Channel)),
    fox:close_connection_pool("pool_2"),
    ok.


declare_queue_test() ->
    Params = setup(),
    fox:create_connection_pool("pool_3", Params),
    {ok, Channel} = fox:get_channel("pool_3"),
    ?assertMatch(#'queue.declare_ok'{queue = <<"my_queue">>}, fox:declare_queue(Channel, <<"my_queue">>)),
    ?assertEqual(ok, fox:declare_queue(Channel, <<"other_queue">>, #{nowait => true})),
    ?assertMatch(#'queue.delete_ok'{}, fox:delete_queue(Channel, <<"my_queue">>)),
    ?assertMatch(#'queue.delete_ok'{}, fox:delete_queue(Channel, <<"other_queue">>)),
    ?assertEqual(ok, amqp_channel:close(Channel)),
    fox:close_connection_pool("pool_3"),
    ok.


bind_queue_test() ->
    Params = setup(),
    fox:create_connection_pool("pool_4", Params),
    {ok, Channel} = fox:get_channel("pool_4"),

    ?assertEqual(ok, fox:declare_exchange(Channel, <<"my_exchange">>)),
    ?assertMatch(#'queue.declare_ok'{}, fox:declare_queue(Channel, <<"my_queue">>)),
    ?assertEqual(ok, fox:bind_queue(Channel, <<"my_queue">>, <<"my_exchange">>, <<"my_key">>)),

    ?assertEqual(ok, fox:unbind_queue(Channel, <<"my_queue">>, <<"my_exchange">>, <<"my_key">>)),
    ?assertMatch(#'queue.delete_ok'{}, fox:delete_queue(Channel, <<"my_queue">>)),
    ?assertEqual(ok, fox:delete_exchange(Channel, <<"my_exchange">>)),

    ?assertEqual(ok, amqp_channel:close(Channel)),
    fox:close_connection_pool("pool_4"),
    ok.


qos_test() ->
    Params = setup(),
    fox:create_connection_pool("pool_5", Params),
    {ok, Channel} = fox:get_channel("pool_5"),

    ?assertEqual(ok, fox:qos("pool_5", #{prefetch_count => 10})),

    ?assertEqual(ok, amqp_channel:close(Channel)),
    fox:close_connection_pool("pool_5"),
    ok.
