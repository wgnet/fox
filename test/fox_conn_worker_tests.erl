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

start_link_test() ->
    Params = setup(),
    Res = fox_conn_worker:start_link(Params),
    ?assertMatch({ok, _}, Res),
    {ok, Pid} = Res,
    ?assertMatch({status, _}, erlang:process_info(Pid, status)),

    ok = fox_conn_worker:stop(Pid),
    ?assertEqual(undefined, erlang:process_info(Pid, status)),

    ok.


