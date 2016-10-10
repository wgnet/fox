-module(fox_subs_router).
-behavior(gen_server).

-export([start_link/0, connection_established/2, subscribe/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    channel :: pid(),
    subscriptions :: map(),
    workers :: map()
}).


%%% module API

-spec start_link() -> gs_start_link_reply().
start_link() ->
    gen_server:start_link(?MODULE, no_args, []).


-spec connection_established(pid(), pid()) -> ok.
connection_established(Pid, Conn) ->
    gen_server:call(Pid, {connection_established, Conn}).


-spec subscribe(pid, #subscription{}) -> ok.
subscribe(Pid, Sub) ->
    gen_server:call(Pid, Sub).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init(_Args) ->
    put('$module', ?MODULE),
    {ok, #state{subscriptions = #{}, workers = #{}}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call({connection_established, Conn}, _From, State) ->
    {ok, Channel} = amqp_connection:open_channel(Conn),
    %% TODO stop all workers
    %% TODO resubscribe subscriptions
    {reply, ok, State#state{channel = Channel}};


handle_call(#subscription{ref = SRef} = Sub,
    _From, #state{channel = undefined, subscriptions = S1} = State) ->
    S2 = S1#{SRef => Sub},
    {reply, ok, State#state{subscriptions = S2}};

handle_call(#subscription{ref = SRef, queues = Queues, subs_module = SModule, subs_args = SArgs} = Sub,
    _From, #state{channel = Channel, subscriptions = S1, workers = W1} = State) ->
    {ok, Worker} = fox_subs_worker:start_link(Channel, SModule, SArgs),
    W2 = lists:foldl(
        fun(Queue, W) ->
            BConsume =
                case Queue of
                    #'basic.consume'{} = B -> B;
                    QueueName when is_binary(QueueName) -> #'basic.consume'{queue = QueueName}
                end,
            #'basic.consume_ok'{consumer_tag = Tag} = amqp_channel:subscribe(Channel, BConsume, self()),
            W#{Tag => {SRef, Worker}}
        end, W1, Queues),
    S2 = S1#{SRef => Sub},
    {reply, ok, State#state{subscriptions = S2, workers = W2}};


handle_call(stop, _From, #state{channel = Channel, workers = Workers} = State) ->
    lists:foreach(
        fun(Tag) ->
            fox_utils:channel_call(Channel, #'basic.cancel'{consumer_tag = Tag})
        end,
        maps:keys(Workers)),

    %% TODO stop all workers
    %% SubsModule:terminate(ChannelPid, CState)
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

handle_info({#'basic.deliver'{consumer_tag = Tag}, _} = Msg, State) ->
    route(Tag, Msg, State),
    {noreply, State};

handle_info(#'basic.cancel'{consumer_tag = Tag} = Msg, State) ->
    route(Tag, Msg, State),
    {noreply, State};

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.


%%% inner functions

route(Tag, Msg, #state{workers = Workers}) ->
    case maps:find(Tag, Workers) of
        {ok, {_SRef, Worker}} -> Worker ! Msg;
        error -> error_logger:error_msg("~p got unknown consumer_tag ~p", [?MODULE, Tag])
    end.
