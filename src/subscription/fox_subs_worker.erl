-module(fox_subs_worker).
-behavior(gen_server).

-export([start_link/1, connection_established/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-callback init(Channel :: pid(), Args :: list()) -> {ok, State :: term()}.
-callback handle(Msg :: term(), Channel :: pid(), State :: term()) -> {ok, State :: term()}.
-callback terminate(Channel :: pid(), State :: term()) -> ok.


%%% module API

-spec start_link(#subscription{}) -> gs_start_link_reply().
start_link(State) ->
    gen_server:start_link(?MODULE, State, []).


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
init(#subscription{queue = Queue} = State) ->
    error_logger:info_msg("fox_subs_worker for queue ~p init", [Queue]),
    put('$module', ?MODULE),
    {ok, State}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #subscription{queue = Queue, channel = Channel, channel_ref = Ref} = State) ->
    error_logger:info_msg("fox_subs_worker for queue ~p stops", [Queue]),
    case Channel of
        undefined -> do_nothing;
        _ -> erlang:demonitor(Ref)
    end,
    State2 = unsubscribe(State),
    {stop, normal, ok, State2#subscription{channel_ref = undefined}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({connection_established, Conn},
    #subscription{
        queue = Queue,
        subs_module = Module,
        subs_args = Args}
        = State) ->
    State2 = unsubscribe(State),
    case amqp_connection:open_channel(Conn) of
        {ok, Channel} -> 
            Ref = erlang:monitor(process, Channel),
            {ok, SubsState} = Module:init(Channel, Args),
            BConsume = 
                case Queue of
                    #'basic.consume'{} = B -> B;
                    QueueName when is_binary(QueueName) ->
                        #'basic.consume'{queue = QueueName}
                end,
            #'basic.consume_ok'{consumer_tag = Tag} =
                amqp_channel:subscribe(Channel, BConsume, self()),
            error_logger:info_msg("fox_subs_worker subscribed to queue ~p", [Queue]),

            {noreply, State2#subscription{
                        connection = Conn,
                        channel = Channel, 
                        channel_ref = Ref, 
                        subs_state = SubsState, 
                        subs_tag = Tag}};
        Other -> 
            error_logger:info_msg("fox_subs_worker can't subscribe to queue ~p, reason: ~p", [Queue, Other]),
            {noreply, State2}
    end;


handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(#'basic.consume_ok'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info({#'basic.deliver'{}, #amqp_msg{}} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info(#'basic.cancel'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info({'DOWN', _Ref, process, _Channel, normal},
            #subscription{queue = Queue} = State) ->
    error_logger:error_msg("fox_subs_worker for queue ~p, channel closed", [Queue]),
    {noreply, State#subscription{channel = undefined, channel_ref = undefined}};

handle_info({'DOWN', Ref, process, Channel, Reason},
            #subscription{
                connection = Conn,
                channel = Channel,
                channel_ref = Ref,
                queue = Queue
            } = State) ->
    fox_priv_utils:error_or_info(Reason, "fox_subs_worker for queue ~p, channel is DOWN: ~p", [Queue, Reason]),
    connection_established(self(), Conn),
    {noreply, State#subscription{channel = undefined, channel_ref = undefined}};

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(Reason, #subscription{queue = Queue}) ->
    fox_priv_utils:error_or_info(Reason, "fox_subs_worker for queue ~p is terminated with reason ~p", [Queue, Reason]),
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
    {ok, SubsState2} = Module:handle(Msg, Channel, SubsState),
    State#subscription{subs_state = SubsState2}.


%%% inner functions

unsubscribe(#subscription{channel = undefined} = State) ->
    State;
unsubscribe(#subscription{
    channel = Channel,
    subs_module = Module,
    subs_state = SubsState,
    subs_tag = Tag}
    = State) ->
    fox_utils:channel_call(Channel, #'basic.cancel'{consumer_tag = Tag}),
    Module:terminate(Channel, SubsState),
    fox_priv_utils:close_channel(Channel),
    State#subscription{channel = undefined}.
