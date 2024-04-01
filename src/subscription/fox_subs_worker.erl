-module(fox_subs_worker).
-behavior(gen_server).

-export([start_link/2, connection_established/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-callback init(Channel :: pid(), Args :: list()) -> {ok, State :: term()}.
-callback handle(Msg :: term(), Channel :: pid(), State :: term()) -> {ok, State :: term()}.
-callback terminate(Channel :: pid(), State :: term()) -> ok.


%%% module API

-spec start_link(#subscription{}, [gen_server:start_opt()]) -> gs_start_link_reply().
start_link(State, StartOptions) ->
    gen_server:start_link(?MODULE, State, StartOptions).


-spec connection_established(pid(), pid()) -> ok.
connection_established(Pid, Conn) ->
    gen_server:cast(Pid, {connection_established, Conn}).


-spec stop(pid()) -> ok.
stop(Pid) ->
    try
        gen_server:call(Pid, stop)
    catch
        exit:{noproc, _} -> ok
    end.


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init(#subscription{ref = SubsRef, pool_name = PoolName, conn_worker = CPid} = State) ->
    logger:info("~s init", [worker_name(State)]),
    put('$module', ?MODULE),
    fox_conn_worker:register_subscriber(CPid, self()),

    SubsMeta = #subs_meta{
        ref = SubsRef,
        conn_worker = CPid,
        subs_worker = self()
    },
    fox_conn_pool:save_subs_meta(PoolName, SubsMeta),
    {ok, State}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #subscription{channel = Channel, channel_ref = Ref} = State) ->
    case Channel of
        undefined -> do_nothing;
        _ -> erlang:demonitor(Ref)
    end,
    State2 = unsubscribe(State),
    logger:info("~s stop", [worker_name(State)]),
    {stop, normal, ok, State2#subscription{channel_ref = undefined}};

handle_call(Any, _From, State) ->
    logger:error("unknown call ~w in ~p", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({connection_established, Conn},
    #subscription{
        basic_consume = BasicConsume,
        subs_module = Module,
        subs_args = Args}
        = State) ->
    WorkerName = worker_name(State),
    logger:info("~s connection_established Conn:~p", [WorkerName, Conn]),
    State2 = unsubscribe(State),

    case amqp_connection:open_channel(Conn) of
        {ok, Channel} ->
            State3 = State2#subscription{connection = Conn},
            logger:info("~s subscribe to queue Channel:~p", [worker_name(State3), Channel]),

            Ref = erlang:monitor(process, Channel),
            {ok, SubsState} = Module:init(Channel, Args),

            #'basic.consume_ok'{consumer_tag = Tag} =
                amqp_channel:subscribe(Channel, BasicConsume, self()),

            {noreply, State3#subscription{
                        channel = Channel,
                        channel_ref = Ref,
                        subs_state = SubsState,
                        subs_tag = Tag}};
        Other ->
            logger:info("~s can't subscribe to queue, reason: ~w", [WorkerName, Other]),
            {noreply, State2}
    end;


handle_cast(Any, State) ->
    logger:error("~s unknown cast ~w", [worker_name(State), Any]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(#'basic.consume_ok'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info({#'basic.deliver'{}, #amqp_msg{}} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info(#'basic.cancel'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info({'DOWN', _Ref, process, _Channel, normal}, State) ->
    logger:error("~s channel has closed", [worker_name(State)]),
    {noreply, State#subscription{channel = undefined, channel_ref = undefined}};

handle_info({'DOWN', Ref, process, Channel, Reason},
            #subscription{
                connection = Conn,
                channel = Channel,
                channel_ref = Ref
            } = State) ->
    fox_priv_utils:error_or_info(Reason, "~s, channel is DOWN: ~w", [worker_name(State), Reason]),

    ConnectionAlive = is_process_alive(Conn),
    if
        ConnectionAlive -> connection_established(self(), Conn);
        true -> do_nothing
    end,
    {noreply, State#subscription{channel = undefined, channel_ref = undefined}};

handle_info(Request, State) ->
    logger:error("~s unknown info ~w", [worker_name(State), Request]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(Reason, State) ->
    unsubscribe(State),
    fox_priv_utils:error_or_info(Reason, "~s terminated with reason ~w", [worker_name(State), Reason]),
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.



handle(Msg,
    #subscription{
        channel = Channel,
        subs_module = Module,
        subs_state = SubsState}
        = State) ->
    logger:info("~s handle event ~p", [worker_name(State), element(1, Msg)]),
    {ok, SubsState2} = Module:handle(Msg, Channel, SubsState),
    State#subscription{subs_state = SubsState2}.


%%% inner functions

worker_name(
  #subscription{
     pool_name = PoolName,
     connection = Conn,
     channel = Channel,
     basic_consume = BasicConsume
}) ->
    #'basic.consume'{queue = QueueName} = BasicConsume,
    FullName = io_lib:format(
                 "fox_subs_worker/~s/~s/Conn:~p/Channel:~p",
                 [PoolName, QueueName, Conn, Channel]
                ),
    unicode:characters_to_binary(FullName).

unsubscribe(#subscription{channel = undefined} = State) ->
    State;
unsubscribe(#subscription{
    channel = Channel,
    subs_module = Module,
    subs_state = SubsState,
    subs_tag = Tag}
    = State) ->
    logger:info("~s unsubscribe from queue", [worker_name(State)]),
    fox_utils:channel_call(Channel, #'basic.cancel'{consumer_tag = Tag}),
    Module:terminate(Channel, SubsState),
    fox_priv_utils:close_channel(Channel),
    State#subscription{channel = undefined}.
