-module(fox_pub_pool).
-behavior(gen_server).

-export([start_link/2, get_channel/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    connection :: pid(),
    connection_ref :: reference(),
    connection_params :: #amqp_params_network{},
    reconnect_attempt = 0 :: non_neg_integer(),
    num_channels :: integer(),
    channels :: queue:queue()
}).


%%% module API

-spec start_link(atom(), #amqp_params_network{}) -> gs_start_link_reply().
start_link(PoolName, ConnectionParams) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:start_link({local, RegName}, ?MODULE, ConnectionParams, []).


-spec get_channel(atom()) -> {ok, pid()} | {error, no_connection}.
get_channel(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, get_channel).


-spec stop(atom()) -> ok.
stop(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, stop).


%%% gen_server API

-spec(init(gs_args()) -> gs_init_reply()).
init(ConnectionParams) ->
    put('$module', ?MODULE),
    {ok, NumChannels} = application:get_env(fox, num_publish_channels),
    herd_rand:init_crypto(),
    self() ! connect,
    {ok, #state{connection_params = ConnectionParams, num_channels = NumChannels, channels = queue:new()}}.


-spec(handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply()).
handle_call(get_channel, _From, #state{connection = undefined} = State) ->
    {reply, {error, no_connection}, State};

handle_call(get_channel, _From, #state{connection = Conn, num_channels = PoolSize, channels = Channels} = State) ->
    NumChannels = queue:len(Channels),
    if
        NumChannels < PoolSize ->
            {ok, Channel} = amqp_connection:open_channel(Conn),
            {reply, {ok, Channel}, State#state{channels = queue:in(Channel, Channels)}};
        true ->
            {{value, Channel}, Channels2} = queue:out(Channels),
            {reply, {ok, Channel}, State#state{channels = queue:in(Channel, Channels2)}}
    end;

handle_call(stop, _From,
    #state{
        connection = Conn,
        connection_ref = Ref,
        channels = Channels}
        = State) ->
    case Conn of
        undefined -> do_nothing;
        Pid ->
            erlang:demonitor(Ref, [flush]),
            fox_priv_utils:close_connection(Pid)
    end,
    lists:foreach(
        fun(Channel) ->
            fox_priv_utils:close_channel(Channel)
        end,
        queue:to_list(Channels)
    ),
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_cast(gs_request(), gs_state()) -> gs_cast_reply()).
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_info(gs_request(), gs_state()) -> gs_info_reply()).
handle_info(connect,
    #state{
        connection = undefined, connection_ref = undefined,
        connection_params = Params, reconnect_attempt = Attempt
    } = State) ->
    case amqp_connection:start(Params) of
        {ok, Conn} ->
            Ref = erlang:monitor(process, Conn),
            {noreply, State#state{
                connection = Conn,
                connection_ref = Ref,
                reconnect_attempt = 0}};
        {error, Reason} ->
            error_logger:error_msg("fox_pub_pool could not connect to ~s ~p",
                [fox_utils:params_network_to_str(Params), Reason]),
            fox_priv_utils:reconnect(Attempt),
            {noreply, State#state{
                connection = undefined,
                connection_ref = undefined,
                reconnect_attempt = Attempt + 1}}
    end;

handle_info({'DOWN', Ref, process, Conn, Reason},
    #state{connection = Conn, connection_ref = Ref, reconnect_attempt = Attempt} = State) ->
    fox_priv_utils:error_or_info(Reason, "fox_pub_worker, connection is DOWN: ~p", [Reason]),
    fox_priv_utils:reconnect(Attempt),
    {noreply, State#state{connection = undefined, connection_ref = undefined}};

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec(terminate(terminate_reason(), gs_state()) -> ok).
terminate(_Reason, _State) ->
    ok.


-spec(code_change(term(), term(), term()) -> gs_code_change_reply()).
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.


