-module(fox_conn_worker).
-behavior(gen_server).

-export([start_link/3, subscribe/2, unsubscribe/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-record(state, {
    connection :: pid(),
    connection_ref :: reference(),
    params_network :: #amqp_params_network{},
    reconnect_attempt = 0 :: non_neg_integer(),
    subs_routers :: queue:queue()
}).


%%% module API

-spec start_link(atom(), integer(), #amqp_params_network{}) -> gs_start_link_reply().
start_link(PoolName, Id, ConnectionParams) ->
    RegName0 = fox_utils:make_reg_name(?MODULE, PoolName),
    RegName = fox_utils:make_reg_name(RegName0, Id),
    gen_server:start_link({local, RegName}, ?MODULE, {PoolName, Id, ConnectionParams}, []).


-spec subscribe(pid(), #subscription{}) -> {ok, reference()} | {error, term()}.
subscribe(Pid, Sub) ->
    gen_server:call(Pid, Sub).


-spec unsubscribe(pid(), reference()) -> ok | {error, term()}.
unsubscribe(Pid, SubscribeRef) ->
    gen_server:call(Pid, {unsubscribe, SubscribeRef}).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({PoolName, ConnectionId, ConnectionParams}) ->
    put('$module', ?MODULE),
    herd_rand:init_crypto(),

    {ok, NumChannels} = application:get_env(fox, num_channels_per_connection),
    Routers = [
        begin
            {ok, Pid} = fox_subs_sup:start_router(PoolName, ConnectionId * 100 + RouterId),
            Pid
        end || RouterId <- lists:seq(1, NumChannels)],

    self() ! connect,
    {ok, #state{params_network = ConnectionParams, subs_routers = queue:from_list(Routers)}}.


handle_call(#subscription{} = Sub, _From,
            #state{connection = Connection} = State) ->
    Reply = case Connection of
                undefined -> % will start subscription later
                    ok;
                _Pid ->
                    case do_subscription(Connection, Sub) of
                        ok ->
                            %% TODO call subs_router
                            ok;
                        {error, Reason} ->
                            {error, Reason}
                    end
            end,
    {reply, Reply, State};

handle_call({unsubscribe, Ref}, _From, #state{} = State) ->
    %% TODO unsubscribe
    {reply, {error, subscription_not_found}, State};

handle_call(stop, _From, #state{connection = Connection,
                                connection_ref = Ref} = State) ->
    case Connection of
        undefined -> do_nothing;
        Pid ->
            %% TODO unsubscribe and close all
            fox_utils:close_connection(Pid)
    end,
    {stop, normal, ok, State#state{connection = undefined, connection_ref = undefined}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(connect,
    #state{
        connection = undefined, connection_ref = undefined,
        params_network = Params, reconnect_attempt = Attempt,
        subs_routers = Routers
    } = State) ->
    case amqp_connection:start(Params) of
        {ok, Conn} ->
            Ref = erlang:monitor(process, Conn),
            [fox_subs_router:connection_established(Pid, Conn) || Pid <- queue:to_list(Routers)],
            {noreply, State#state{connection = Conn, connection_ref = Ref, reconnect_attempt = 0}};
        {error, Reason} ->
            error_logger:error_msg("fox_conn_worker could not connect to ~s ~p",
                                   [fox_utils:params_network_to_str(Params), Reason]),
            {ok, MaxTimeout} = application:get_env(fox, max_reconnect_timeout),
            {ok, MinTimeout} = application:get_env(fox, min_reconnect_timeout),
            Timeout = herd_reconnect:exp_backoff(Attempt, MinTimeout, MaxTimeout),
            error_logger:warning_msg("fox_conn_worker reconnect after ~p attempt ~p", [Timeout, Attempt]),
            erlang:send_after(Timeout, self(), connect),
            {noreply, State#state{connection = undefined, connection_ref = undefined,
                                  reconnect_attempt = Attempt + 1}}
    end;

handle_info({'DOWN', Ref, process, Connection, Reason},
            #state{connection = Connection, connection_ref = Ref} = State) ->
    error_or_info(Reason, "fox_conn_worker, connection is DOWN: ~p", [Reason]),
    self() ! connect,
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


%% inner functions

-spec do_subscription(pid(), #subscription{}) -> {ok, #subscription{}} | {error, term()}.
do_subscription(Connection, Sub) ->
    %% TODO
    Sub.

-spec close_subscription(#subscription{}) -> #subscription{}.
close_subscription(#subscription{} = Sub) ->
    %% TODO
    Sub.


error_or_info(normal, ErrMsg, Params) ->
    error_logger:info_msg(ErrMsg, Params);

error_or_info(_, ErrMsg, Params) ->
    error_logger:error_msg(ErrMsg, Params).
