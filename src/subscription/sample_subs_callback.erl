-module(sample_subs_callback).
-behaviour(fox_subs_worker).

-export([init/2, handle/3, terminate/2]).

-include("fox.hrl").

-type(state() :: term()).


%%% module API

-spec init(pid(), list()) -> {ok, state()}.
init(Channel, Args) ->
    error_logger:info_msg("sample_subs_callback:init channel:~p args:~p", [Channel, Args]),

    Exchange = <<"my_exchange">>,
    Queue1 = <<"my_queue">>,
    Queue2 = <<"other_queue">>,
    RoutingKey1 = <<"my_key">>,
    RoutingKey2 = <<"my_key_2">>,

    ok = fox:declare_exchange(Channel, Exchange),

    #'queue.declare_ok'{} = fox:declare_queue(Channel, Queue1),
    ok = fox:bind_queue(Channel, Queue1, Exchange, RoutingKey1),

    #'queue.declare_ok'{} = fox:declare_queue(Channel, Queue2),
    ok = fox:bind_queue(Channel, Queue2, Exchange, RoutingKey2),

    State = {Exchange, [{Queue1, RoutingKey1}, {Queue2, RoutingKey2}]},
    {ok, State}.


-spec handle(term(), pid(), state()) -> {ok, state()}.
handle({#'basic.deliver'{delivery_tag = Tag}, #amqp_msg{payload = Payload}}, Channel, State) ->
    error_logger:info_msg("sample_subs_callback:handle basic.deliver, Payload:~p", [Payload]),
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag}),
    {ok, State};

handle(#'basic.cancel'{} = Data, _Channel, State) ->
    error_logger:info_msg("sample_subs_callback:handle basic.cancel, Data:~p", [Data]),
    {ok, State};

handle(Data, _Channel, State) ->
    error_logger:error_msg("sample_subs_callback:handle, unknown data:~p", [Data]),
    {ok, State}.


-spec terminate(pid(), state()) -> ok.
terminate(Channel, State) ->
    error_logger:info_msg("sample_subs_callback:terminate channel:~p, state:~p", [Channel, State]),
    {Exchange, Bindings} = State,
    lists:foreach(fun({Queue, RoutingKey}) ->
                          fox:unbind_queue(Channel, Queue, Exchange, RoutingKey),
                          fox:delete_queue(Channel, Queue)
                  end, Bindings),
    fox:delete_exchange(Channel, Exchange),
    ok.
