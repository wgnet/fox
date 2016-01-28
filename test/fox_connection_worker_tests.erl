-module(fox_connection_worker_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").


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
    ?assertEqual({num_channels, 0}, fox_connection_worker:get_info(Pid)),

    {ok, C1} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({num_channels, 1}, fox_connection_worker:get_info(Pid)),

    {ok, C2} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({num_channels, 2}, fox_connection_worker:get_info(Pid)),

    {ok, C3} = fox_connection_worker:create_channel(Pid),
    ?assertEqual({num_channels, 3}, fox_connection_worker:get_info(Pid)),

    amqp_channel:close(C1),
    timer:sleep(100),
    ?assertEqual({num_channels, 2}, fox_connection_worker:get_info(Pid)),

    amqp_channel:close(C2),
    timer:sleep(100),
    ?assertEqual({num_channels, 1}, fox_connection_worker:get_info(Pid)),

    amqp_channel:close(C3),
    timer:sleep(100),
    ?assertEqual({num_channels, 0}, fox_connection_worker:get_info(Pid)),

    ok = fox_connection_worker:stop(Pid),
    ok.
