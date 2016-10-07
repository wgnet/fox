-module(sample_subscription_callback).
-behaviour(fox_channel_consumer).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").

-type(state() :: term()).


%%% module API

-spec init(pid(), list()) -> {ok, state()}.
init(ChannelPid, Args) ->
    error_logger:info_msg("sample_subscription_callback:init channel:~p args:~p", [ChannelPid, Args]),

    Exchange = <<"my_exchange">>,
    Queue1 = <<"my_queue">>,
    Queue2 = <<"other_queue">>,
    RoutingKey1 = <<"my_key">>,
    RoutingKey2 = <<"my_key_2">>,

    ok = fox:declare_exchange(ChannelPid, Exchange),

    #'queue.declare_ok'{} = fox:declare_queue(ChannelPid, Queue1),
    ok = fox:bind_queue(ChannelPid, Queue1, Exchange, RoutingKey1),

    #'queue.declare_ok'{} = fox:declare_queue(ChannelPid, Queue2),
    ok = fox:bind_queue(ChannelPid, Queue2, Exchange, RoutingKey2),

    State = {Exchange, [{Queue1, RoutingKey1}, {Queue2, RoutingKey2}]},
    {ok, State}.


-spec handle(term(), pid(), state()) -> {ok, state()}.
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, ChannelPid, State) ->
    error_logger:info_msg("sample_subscription_callback:handle basic.deliver, Payload:~p", [Payload]),
    amqp_channel:cast(ChannelPid, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};

handle(#'basic.cancel'{} = Data, _ChannelPid, State) ->
    error_logger:info_msg("sample_subscription_callback:handle basic.cancel, Data:~p", [Data]),
    {ok, State};

handle(Data, _ChannelPid, State) ->
    error_logger:error_msg("sample_subscription_callback:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), state()) -> ok.
terminate(ChannelPid, State) ->
    error_logger:info_msg("sample_subscription_callback:terminate channel:~p, state:~p", [ChannelPid, State]),
    {Exchange, Bindings} = State,
    lists:foreach(fun({Queue, RoutingKey}) ->
                          fox:unbind_queue(ChannelPid, Queue, Exchange, RoutingKey),
                          fox:delete_queue(ChannelPid, Queue)
                  end, Bindings),
    fox:delete_exchange(ChannelPid, Exchange),
    ok.
