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


%%% module API

-spec start_link(atom(), integer(), #amqp_params_network{}) -> gs_start_link_reply().
start_link(PoolName, Id, ConnParams) ->
    RegName0 = fox_utils:make_reg_name(?MODULE, PoolName),
    RegName = fox_utils:make_reg_name(RegName0, Id),
    gen_server:start_link({local, RegName}, ?MODULE, {RegName, ConnParams}, []).


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
init({RegName, ConnParams}) ->
    put('$module', ?MODULE),
    self() ! connect,
    {ok, #conn_worker_state{
            connection_ready = false,
            connection_params = ConnParams, 
            registered_name = RegName
           }}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #conn_worker_state{connection = Conn, connection_ref = Ref} = State) ->
    case Conn of
        undefined -> do_nothing;
        Pid ->
            erlang:demonitor(Ref, [flush]),
            fox_priv_utils:close_connection(Pid)
    end,
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    logger:error("unknown call ~w in ~p", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({register_subscriber, Pid}, 
            #conn_worker_state{connection_ready = false, subscribers = Subs} = State
           ) ->
    {noreply, State#conn_worker_state{subscribers = [Pid | Subs]}};

handle_cast({register_subscriber, Pid}, 
            #conn_worker_state{connection_ready = true, connection = Conn, subscribers = Subs} = State
           ) ->
    fox_subs_worker:connection_established(Pid, Conn),
    {noreply, State#conn_worker_state{subscribers = [Pid | Subs]}};

handle_cast({remove_subscriber, Pid}, #conn_worker_state{subscribers = Subs} = State) ->
    Subs2 = lists:delete(Pid, Subs),
    {noreply, State#conn_worker_state{subscribers = Subs2}};

handle_cast(Any, State) ->
    logger:error("unknown cast ~w in ~p", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(connect,
    #conn_worker_state{
        connection = undefined, connection_ref = undefined,
        connection_params = Params, reconnect_attempt = Attempt,
        registered_name = RegName
    } = State) ->
    SParams = fox_utils:params_network_to_str(Params),
    case amqp_connection:start(Params) of
        {ok, Conn} ->
            Ref = erlang:monitor(process, Conn),
            logger:notice("~s connected to ~s", [RegName, SParams]),
            %% Need a small pause here 
            %% because RabbitMQ is not ready to accept subscriptions 
            %% immediatelly after restart.
            {ok, SubscribeTimeout} = application:get_env(fox, subscribe_timeout),
            erlang:send_after(SubscribeTimeout, self(), notify_subscribers),
            State2 = State#conn_worker_state{
                connection = Conn,
                connection_ref = Ref,
                connection_ready = false,
                reconnect_attempt = 0
            },
            {noreply, State2};
        {error, Reason} ->
            logger:error("~s could not connect to ~s ~w", [RegName, SParams, Reason]),
            fox_priv_utils:reconnect(Attempt),
            State2 = State#conn_worker_state{
                connection = undefined,
                connection_ref = undefined,
                connection_ready = true,
                reconnect_attempt = Attempt + 1
            },
            {noreply, State2}
    end;

handle_info(notify_subscribers,
    #conn_worker_state{
        connection = Conn,
        subscribers = Subscribers
    } = State) ->
    [fox_subs_worker:connection_established(Pid, Conn) || Pid <- Subscribers],
    {noreply, State#conn_worker_state{connection_ready = true}};

handle_info({'DOWN', Ref, process, Conn, Reason},
            #conn_worker_state{
                connection = Conn,
                connection_ref = Ref,
                reconnect_attempt = Attempt,
                registered_name = RegName
            } = State) ->
    fox_priv_utils:error_or_info(Reason, "~s, connection is DOWN: ~0p", [RegName, Reason]),
    fox_priv_utils:reconnect(Attempt),
    {noreply, State#conn_worker_state{
                connection_ready = false, 
                connection = undefined, 
                connection_ref = undefined}};


handle_info(Request, State) ->
    logger:error("unknown info ~w in ~p", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.
