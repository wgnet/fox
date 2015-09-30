-module(fox_connection_worker_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

setup() ->
    application:ensure_all_started(amqp_client),
    fox_utils:map_to_params_network(#{host => "localhost",
                                      port => 5672,
                                      virtual_host => <<"/">>,
                                      username => <<"guest">>,
                                      password => <<"guest">>}).

start_link_test() ->
    Params = setup(),
    Res = fox_connection_worker:start_link(Params),
    ?assertMatch({ok, _}, Res),
    {ok, Pid} = Res,
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),

    ok = fox_connection_worker:stop(Pid),
    ?assertEqual(undefined, erlang:process_info(Pid, status)),

    ok.


channels_test() ->
    Params = setup(),
    {ok, Pid} = fox_connection_worker:start_link(Params),
    ?assertEqual({ok, 0}, fox_connection_worker:get_num_channels(Pid)),

    {ok, C1} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({ok, 1}, fox_connection_worker:get_num_channels(Pid)),

    {ok, C2} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({ok, 2}, fox_connection_worker:get_num_channels(Pid)),

    {ok, C3} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({ok, 3}, fox_connection_worker:get_num_channels(Pid)),

    amqp_channel:close(C1),
    ?assertEqual({ok, 2}, fox_connection_worker:get_num_channels(Pid)),

    amqp_channel:close(C2),
    ?assertEqual({ok, 1}, fox_connection_worker:get_num_channels(Pid)),

    amqp_channel:close(C3),
    ?assertEqual({ok, 0}, fox_connection_worker:get_num_channels(Pid)),

    ok = fox_connection_worker:stop(Pid),
    ok.
