-module(fox_pub_pool).
-behavior(gen_server).

-export([start_link/2, get_channel/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    connection :: pid() | undefined,
    connection_ref :: reference() | undefined,
    connection_params :: #amqp_params_network{},
    reconnect_attempt = 0 :: non_neg_integer(),
    num_channels :: integer(),
    channels :: queue:queue(),
    registered_name :: atom()
}).


%%% module API

-spec start_link(atom(), #amqp_params_network{}) -> gs_start_link_reply().
start_link(PoolName, ConnectionParams) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:start_link({local, RegName}, ?MODULE, {RegName, ConnectionParams}, []).


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
init({RegName, ConnectionParams}) ->
    put('$module', ?MODULE),
    {ok, NumChannels} = application:get_env(fox, num_publish_channels),
    self() ! connect,
    {
        ok,
        #state{
            connection_params = ConnectionParams,
            num_channels = NumChannels,
            registered_name = RegName
        }
    }.


-spec(handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply()).
handle_call(get_channel, _From, #state{connection = undefined} = State) ->
    {reply, {error, no_connection}, State};

handle_call(get_channel, _From, #state{connection = Conn, num_channels = PoolSize, channels = Channels} = State) ->
    {Channel, Channels1} = handle_get_channel(Channels, PoolSize, Conn),
    {reply, {ok, Channel}, State#state{channels = Channels1}};

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
    logger:error("unknown call ~w in ~p", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_cast(gs_request(), gs_state()) -> gs_cast_reply()).
handle_cast(Any, State) ->
    logger:error("unknown cast ~w in ~p", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_info(gs_request(), gs_state()) -> gs_info_reply()).
handle_info(connect,
    #state{
        connection = undefined,
        connection_ref = undefined,
        connection_params = Params,
        reconnect_attempt = Attempt,
        registered_name = RegName
    } = State) ->
    SParams = fox_utils:params_network_to_str(Params),
    case amqp_connection:start(Params) of
        {ok, Conn} ->
            Ref = erlang:monitor(process, Conn),
            logger:notice("~s connected to ~s", [RegName, SParams]),
            {noreply, State#state{
                connection = Conn,
                connection_ref = Ref,
                reconnect_attempt = 0,
                channels = queue:new()
            }};
        {error, Reason} ->
            logger:error("~s could not connect to ~s ~w", [RegName, SParams, Reason]),
            fox_priv_utils:reconnect(Attempt),
            {noreply, State#state{
                connection = undefined,
                connection_ref = undefined,
                reconnect_attempt = Attempt + 1}}
    end;

handle_info({'DOWN', Ref, process, Conn, Reason},
    #state{
        connection = Conn,
        connection_ref = Ref,
        reconnect_attempt = Attempt,
        channels = Channels,
        registered_name = RegName
    } = State) ->
    lists:foreach(
        fun(Channel) ->
            fox_priv_utils:close_channel(Channel)
        end,
        queue:to_list(Channels)),
    fox_priv_utils:error_or_info(Reason, "~s, connection is DOWN: ~w", [RegName, Reason]),
    fox_priv_utils:reconnect(Attempt),
    {noreply, State#state{connection = undefined, connection_ref = undefined, channels = undefined}};

handle_info(Request, State) ->
    logger:error("unknown info ~w in ~p", [Request, ?MODULE]),
    {noreply, State}.


-spec(terminate(terminate_reason(), gs_state()) -> ok).
terminate(_Reason, _State) ->
    ok.


-spec(code_change(term(), term(), term()) -> gs_code_change_reply()).
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.


%% internal functions

-spec handle_get_channel(queue:queue(pid()), pos_integer(), pid()) -> {pid(), queue:queue(pid())}.
handle_get_channel(Channels, PoolSize, Connection) ->
    NumChannels = queue:len(Channels),

    {Channel1, Channels2} = case NumChannels < PoolSize of
        true ->
            {ok, Channel} = amqp_connection:open_channel(Connection),
            {Channel, Channels};
        false ->
            {{value, Channel}, Channels1} = queue:out(Channels),
            {Channel, Channels1}
    end,

    case is_process_alive(Channel1) of
        true ->
            {Channel1, queue:in(Channel1, Channels2)};
        false ->
            logger:info(
                "Fox channel ~p seems to be dead. Drop it and create new",
                [Channel1]
            ),
            handle_get_channel(Channels2, PoolSize, Connection)
    end.
