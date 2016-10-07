-module(fox_utils_tests).

-include_lib("eunit/include/eunit.hrl").

-include("fox.hrl").


name_to_atom_test() ->
    ?assertEqual(some_pool, fox_utils:name_to_atom(<<"some_pool">>)),
    ?assertEqual(other_pool, fox_utils:name_to_atom("other_pool")),
    ?assertEqual(pool_2, fox_utils:name_to_atom(pool_2)),
    ok.


map_to_params_network_test() ->
    P1 = #{host => "localhost",
           port => 5672,
           virtual_host => <<"/">>,
           username => <<"guest">>,
           password => <<"guest">>
          },
    PN1 = #amqp_params_network{
             host = "localhost",
             port = 5672,
             virtual_host = <<"/">>,
             username = <<"guest">>,
             password = <<"guest">>,
             heartbeat = 0,
             connection_timeout = 10000,
             channel_max = 0,
             frame_max = 0,
             ssl_options = none,
             client_properties = [],
             socket_options = []
            },
    ?assertMatch(PN1, fox_utils:map_to_params_network(P1)),

    P2 = P1#{username := <<"Bill">>, heartbeat => 15, frame_max => 42},
    PN2 = PN1#amqp_params_network{username = <<"Bill">>, heartbeat = 15, frame_max = 42},
    ?assertMatch(PN2, fox_utils:map_to_params_network(P2)),

    ok.


params_network_to_str_test() ->
    PN1 = #amqp_params_network{
             host = "localhost",
             port = 5672,
             virtual_host = <<"/">>,
             username = <<"guest">>
            },
    ?assertEqual("guest@localhost:5672/", lists:flatten(fox_utils:params_network_to_str(PN1))),
    PN2 = #amqp_params_network{
             host = "some.where",
             port = 1234,
             virtual_host = <<"/main">>,
             username = <<"bob">>
            },
    ?assertEqual("bob@some.where:1234/main", lists:flatten(fox_utils:params_network_to_str(PN2))),
    ok.


map_to_exchange_declare_test() ->
    P1 = #{aaa => 5, bbb => 42},
    ED1 = #'exchange.declare'{
             ticket = 0,
             exchange = <<>>,
             type = <<"direct">>,
             passive = false,
             durable = false,
             auto_delete = false,
             internal = false,
             nowait = false,
             arguments = []
            },
    ?assertMatch(ED1, fox_utils:map_to_exchange_declare(P1)),
    P2 = #{exchange => <<"my_exchange">>,
           passive => true,
           auto_delete => true,
           ccc => 777
          },
    ED2 = ED1#'exchange.declare'{exchange = <<"my_exchange">>, passive = true, auto_delete = true},
    ?assertMatch(ED2, fox_utils:map_to_exchange_declare(P2)),
    ok.


map_to_exchange_delete_test() ->
    P1 = #{aaa => 5, bbb => 42},
    ED1 = #'exchange.delete'{
             ticket = 0,
             exchange = <<>>,
             if_unused = false,
             nowait = false
            },
    ?assertMatch(ED1, fox_utils:map_to_exchange_delete(P1)),
    P2 = #{exchange => <<"my_exchange">>,
           passive => true,
           nowait => true,
           ccc => 777
          },
    ED2 = ED1#'exchange.delete'{exchange = <<"my_exchange">>, nowait = true},
    ?assertMatch(ED2, fox_utils:map_to_exchange_delete(P2)),
    ok.


map_to_queue_declare_test() ->
    P1 = #{aaa => 5, bbb => 42},
    ED1 = #'queue.declare'{
             ticket = 0,
             queue = <<>>,
             passive = false,
             durable = false,
             exclusive = false,
             auto_delete = false,
             nowait = false,
             arguments = []
            },
    ?assertMatch(ED1, fox_utils:map_to_queue_declare(P1)),
    P2 = #{queue => <<"my_queue">>,
           passive => true,
           auto_delete => true,
           ccc => 777
          },
    ED2 = ED1#'queue.declare'{queue = <<"my_queue">>, passive = true, auto_delete = true},
    ?assertMatch(ED2, fox_utils:map_to_queue_declare(P2)),
    ok.


map_to_queue_delete_test() ->
    P1 = #{aaa => 5, bbb => 42},
    ED1 = #'queue.delete'{
             ticket = 0,
             queue = <<>>,
             if_unused = false,
             if_empty = false,
             nowait = false
            },
    ?assertMatch(ED1, fox_utils:map_to_queue_delete(P1)),
    P2 = #{queue => <<"my_queue">>,
           passive => true,
           nowait => true,
           ccc => 777,
           if_empty => true
          },
    ED2 = ED1#'queue.delete'{queue = <<"my_queue">>, nowait = true, if_empty = true},
    ?assertMatch(ED2, fox_utils:map_to_queue_delete(P2)),
    ok.


map_to_queue_bind_test() ->
    P1 = #{ticket => 42, bla_bla_bla => 43, arguments => [1,2,3]},
    QB1 = #'queue.bind'{
       ticket = 42,
       queue = <<>>,
       exchange = <<>>,
       routing_key = <<>>,
       nowait = false,
       arguments = [1,2,3]
      },
    ?assertMatch(QB1, fox_utils:map_to_queue_bind(P1)),
    P2 = #{queue => <<"my_queue">>, exchange => <<"my_exchange">>, routing_key => <<"my_key">>},
    QB2 = #'queue.bind'{
       ticket = 0,
       queue = <<"my_queue">>,
       exchange = <<"my_exchange">>,
       routing_key = <<"my_key">>,
       nowait = false,
       arguments = []
      },
    ?assertMatch(QB2, fox_utils:map_to_queue_bind(P2)),
    ok.


map_to_queue_unbind_test() ->
    P1 = #{ticket => 42, bla_bla_bla => 43, arguments => [1,2,3]},
    QB1 = #'queue.unbind'{
       ticket = 42,
       queue = <<>>,
       exchange = <<>>,
       routing_key = <<>>,
       arguments = [1,2,3]
      },
    ?assertMatch(QB1, fox_utils:map_to_queue_unbind(P1)),
    P2 = #{queue => <<"my_queue">>, exchange => <<"my_exchange">>, routing_key => <<"my_key">>},
    QB2 = #'queue.unbind'{
       ticket = 0,
       queue = <<"my_queue">>,
       exchange = <<"my_exchange">>,
       routing_key = <<"my_key">>,
       arguments = []
      },
    ?assertMatch(QB2, fox_utils:map_to_queue_unbind(P2)),
    ok.


map_to_basic_publish_test() ->
    P = #{exchange => <<"my_exchange">>, mandatory => true},
    BP = #'basic.publish'{
       ticket = 0,
       exchange = <<"my_exchange">>,
       routing_key = <<>>,
       mandatory = true,
       immediate = false
      },
    ?assertMatch(BP, fox_utils:map_to_basic_publish(P)),
    ok.


map_to_pbasic_test() ->
    P1 = #{},
    PB1 = #'P_basic'{},
    ?assertMatch(PB1, fox_utils:map_to_pbasic(P1)),
    P2 = #{priority => 5, user_id => 42, bla_bla_bla => 777},
    PB2 = #'P_basic'{priority = 5, user_id = 42},
    ?assertMatch(PB2, fox_utils:map_to_pbasic(P2)),
    ok.
