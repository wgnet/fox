-module(subscribe_test).
-behaviour(fox_subs_router).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").

-record(state, {counter = 0 :: integer(),
                exchange :: binary(),
                queue :: binary(),
                routing_key :: binary()
               }).


%%% module API

-spec init(pid(), list()) -> {ok, #state{}}.
init(ChannelPid, Args) ->
    ct:log("subscribe_test:init channel:~p args:~p", [ChannelPid, Args]),
    Counter = ets:info(subscribe_test_ets, size) + 1,
    ets:insert(subscribe_test_ets, {Counter, init, Args}),

    State = #state{counter = Counter + 1,
                   exchange = <<"my_exchange">>,
                   queue = <<"my_queue">>,
                   routing_key = <<"my_key">>},
    ok = fox:declare_exchange(ChannelPid, State#state.exchange),
    #'queue.declare_ok'{} = fox:declare_queue(ChannelPid, State#state.queue),
    ok = fox:bind_queue(ChannelPid, State#state.queue, State#state.exchange, State#state.routing_key),

    {ok, State}.


-spec handle(term(), pid(), #state{}) -> {ok, #state{}}.
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, #state{counter = Counter} = State) ->
    ct:log("subscribe_test:handle basic.deliver, Payload:~p", [Payload]),
    ets:insert(subscribe_test_ets, {Counter, handle_basic_deliver, Payload}),
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    {ok, State#state{counter = Counter + 1}};

handle(Data, _ChannelPid, State) ->
    error_logger:error_msg("subscribe_test:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), #state{}) -> ok.
terminate(ChannelPid, #state{counter = Counter, exchange = Exchange, queue = Queue, routing_key = RoutingKey}) ->
    ct:log("subscribe_test:terminate channel:~p", [ChannelPid]),
    ets:insert(subscribe_test_ets, {Counter, terminate}),
    fox:unbind_queue(ChannelPid, Queue, Exchange, RoutingKey),
    fox:delete_queue(ChannelPid, Queue),
    fox:delete_exchange(ChannelPid, Exchange),
    ok.
