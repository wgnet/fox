-module(sample_channel_consumer).
-behaviour(fox_channel_consumer).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-type(state() :: term()).


%%% module API

-spec init(pid(), list()) -> {ok, state()} | {subscribe, binary(), state()}.
init(ChannelPid, Args) ->
    ?d("sample_channel_consumer:init channel:~p args:~p", [ChannelPid, Args]),

    Exchange = <<"my_exchange">>,
    Queue = <<"my_queue">>,
    RoutingKey = <<"my_key">>,

    ok = fox:declare_exchange(ChannelPid, Exchange),
    #'queue.declare_ok'{} = amqp_channel:call(ChannelPid, #'queue.declare'{queue = Queue}),
    #'queue.bind_ok'{} =
        amqp_channel:call(ChannelPid, #'queue.bind'{queue = Queue,
                                                    exchange = Exchange,
                                                    routing_key = RoutingKey}),
    State = [],
    {subscribe, Queue, State}.


-spec handle(term(), pid(), state()) -> {ok, state()}.
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, State) ->
    ?d("sample_channel_consumer:handle basic.deliver, Payload:~p", [Payload]),
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};

handle(Data, _ChannelPid, State) ->
    error_logger:error_msg("sample_channel_consumer:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), state()) -> ok.
terminate(ChannelPid, State) ->
    ?d("sample_channel_consumer:terminate channel:~p, state:~p", [ChannelPid, State]),
    ok.
