-module(subscribe_test).
-behaviour(fox_subs_worker).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").

-record(state, {counter = 0 :: integer(),
                exchange :: binary(),
                queue :: binary(),
                routing_key :: binary()
               }).


%%% module API

-spec init(pid(), list()) -> {ok, #state{}}.
init(Channel, Args) ->
    ct:log("subscribe_test:init channel:~p args:~p", [Channel, Args]),
    Counter = ets:info(subscribe_test_ets, size) + 1,
    ets:insert(subscribe_test_ets, {Counter, init, Args}),

    Exchange = <<"my_exchange">>,
    Queue = <<"my_queue">>,
    RK = <<"my_key">>,

    ok = fox:declare_exchange(Channel, Exchange),
    #'queue.declare_ok'{} = fox:declare_queue(Channel, Queue),
    ok = fox:bind_queue(Channel, Queue, Exchange, RK),

    {ok, #state{counter = Counter + 1, exchange = Exchange, queue = Queue, routing_key = RK}}.


-spec handle(term(), pid(), #state{}) -> {ok, #state{}}.
handle(#'basic.consume_ok'{}, _Channel, State) ->
    {ok, State};

handle(#'basic.cancel'{}, _Channel, State) ->
    {ok, State};

handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}},
    Channel, #state{counter = Counter} = State) ->
    ct:log("subscribe_test:handle basic.deliver, Payload:~p", [Payload]),
    ets:insert(subscribe_test_ets, {Counter, handle_basic_deliver, Payload}),
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
    {ok, State#state{counter = Counter + 1}};

handle(Data, _ChannelPid, State) ->
    error_logger:error_msg("subscribe_test:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), #state{}) -> ok.
terminate(Channel, #state{counter = Counter, exchange = Exchange, queue = Queue, routing_key = RoutingKey}) ->
    ct:log("subscribe_test:terminate channel:~p", [Channel]),
    ets:insert(subscribe_test_ets, {Counter, terminate}),
    fox:unbind_queue(Channel, Queue, Exchange, RoutingKey),
    fox:delete_queue(Channel, Queue),
    fox:delete_exchange(Channel, Exchange),
    ok.
