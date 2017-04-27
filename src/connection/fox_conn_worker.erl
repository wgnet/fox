%%%
%%% Creates connection to rabbit, monitor it, reconnect if needed.
%%% Keep list of subscriptions, init them with connection when it ready
%%%

-module(fox_conn_worker).
-behavior(gen_server).

-export([start_link/3, register_subscriber/2, remove_subscriber/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    connection :: pid() | undefined,
    connection_ref :: reference() | undefined,
    connection_params :: #amqp_params_network{},
    reconnect_attempt = 0 :: non_neg_integer(),
    subscribers = [] :: [pid()]
}).


%%% module API

-spec start_link(atom(), integer(), #amqp_params_network{}) -> gs_start_link_reply().
start_link(PoolName, Id, ConnParams) ->
    RegName0 = fox_utils:make_reg_name(?MODULE, PoolName),
    RegName = fox_utils:make_reg_name(RegName0, Id),
    gen_server:start_link({local, RegName}, ?MODULE, ConnParams, []).


-spec register_subscriber(pid(), pid()) -> ok.
register_subscriber(ConnWorkerPid, SubsWorkerPid) ->
    gen_server:cast(ConnWorkerPid, {register_subscriber, SubsWorkerPid}).


-spec remove_subscriber(pid(), pid()) -> ok.
remove_subscriber(ConnWorkerPid, SubsWorkerPid) ->
    gen_server:cast(ConnWorkerPid, {remove_subscriber, SubsWorkerPid}).


-spec stop(pid()) -> ok.
stop(Pid) ->
    try
        gen_server:call(Pid, stop)
    catch
        exit:{noproc, _} -> ok
    end.


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init(ConnParams) ->
    put('$module', ?MODULE),
    herd_rand:init_crypto(),
    self() ! connect,
    {ok, #state{connection_params = ConnParams}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #state{connection = Conn, connection_ref = Ref} = State) ->
    case Conn of
        undefined -> do_nothing;
        Pid ->
            erlang:demonitor(Ref, [flush]),
            fox_priv_utils:close_connection(Pid)
    end,
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({register_subscriber, Pid}, #state{connection = Conn, subscribers = Subs} = State) ->
    case Conn of
        undefined -> do_nothing;
        _ -> fox_subs_worker:connection_established(Pid, Conn)
    end,
    {noreply, State#state{subscribers = [Pid | Subs]}};

handle_cast({remove_subscriber, Pid}, #state{subscribers = Subs} = State) ->
    Subs2 = lists:delete(Pid, Subs),
    {noreply, State#state{subscribers = Subs2}};

handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(connect,
    #state{
        connection = undefined, connection_ref = undefined,
        connection_params = Params, reconnect_attempt = Attempt,
        subscribers = Subscribers
    } = State) ->
    SParams = fox_utils:params_network_to_str(Params),
    case amqp_connection:start(Params) of
        {ok, Conn} ->
            Ref = erlang:monitor(process, Conn),
            error_logger:info_msg("fox_conn_worker connected to ~s", [SParams]),
            [fox_subs_worker:connection_established(Pid, Conn) || Pid <- Subscribers],
            {noreply, State#state{
                connection = Conn,
                connection_ref = Ref,
                reconnect_attempt = 0}};
        {error, Reason} ->
            error_logger:error_msg("fox_conn_worker could not connect to ~s ~p", [SParams, Reason]),
            fox_priv_utils:reconnect(Attempt),
            {noreply, State#state{
                connection = undefined,
                connection_ref = undefined,
                reconnect_attempt = Attempt + 1}}
    end;

handle_info({'DOWN', Ref, process, Conn, Reason},
            #state{connection = Conn, connection_ref = Ref, reconnect_attempt = Attempt} = State) ->
    fox_priv_utils:error_or_info(Reason, "fox_conn_worker, connection is DOWN: ~p", [Reason]),
    fox_priv_utils:reconnect(Attempt),
    {noreply, State#state{connection = undefined, connection_ref = undefined}};


handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

