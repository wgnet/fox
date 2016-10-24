-module(subs_test_callback).
-behaviour(fox_subs_worker).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").

-record(state, {
    table :: ets:tab(),
    exchange :: binary(),
    queue :: binary(),
    routing_key :: binary()
}).


%%% module API

-spec init(pid(), list()) -> {ok, #state{}}.
init(Channel, Args) ->
    {Table, Exchange, Queue, RK} = Args,
    ct:log("subscribe_test:init channel:~p args:~p", [Channel, Args]),
    log(Table, {Queue, init, Args}),

    ok = fox:declare_exchange(Channel, Exchange),
    #'queue.declare_ok'{} = fox:declare_queue(Channel, Queue),
    ok = fox:bind_queue(Channel, Queue, Exchange, RK),

    {ok, #state{table = Table, exchange = Exchange, queue = Queue, routing_key = RK}}.


-spec handle(term(), pid(), #state{}) -> {ok, #state{}}.
handle(#'basic.consume_ok'{}, _Channel, State) ->
    {ok, State};

handle(#'basic.cancel'{}, _Channel, State) ->
    {ok, State};

handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}},
    Channel, #state{table = Table, queue = Queue} = State) ->
    ct:log("subscribe_test:handle basic.deliver, Payload:~p", [Payload]),
    log(Table, {Queue, handle_basic_deliver, Payload}),
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};

handle(Data, _ChannelPid, State) ->
    error_logger:error_msg("subscribe_test:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), #state{}) -> ok.
terminate(Channel, #state{table = Table, exchange = Exchange, queue = Queue, routing_key = RK}) ->
    ct:log("subscribe_test:terminate channel:~p", [Channel]),
    log(Table, {Queue, terminate}),
    fox:unbind_queue(Channel, Queue, Exchange, RK),
    fox:delete_queue(Channel, Queue),
    fox:delete_exchange(Channel, Exchange),
    ok.


log(Table, Data) ->
    Counter = ets:info(Table, size) + 1,
    Data2 = list_to_tuple([Counter | tuple_to_list(Data)]),
    ets:insert(Table, Data2).
