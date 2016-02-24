-module(fox_publish_channels_pool).
-behavior(gen_server).

-export([start_link/2, get_channel/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").

-record(state, {
          pool_name :: atom(),
          pool_size :: integer(),
          num_connections_ready = 0 :: integer(),
          ready_channels = [] :: [pid()],
          used_channels = [] :: [pid()]
         }).


%%% module API

-spec(start_link(atom(), integer()) -> gs_init_reply()).
start_link(PoolName, PoolSize) ->
    gen_server:start_link(?MODULE, {PoolName, PoolSize}, []).


-spec get_channel(pid()) -> {ok, pid()} | {error, no_connection}.
get_channel(Pid) ->
    gen_server:call(Pid, get_channel).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec(init(gs_args()) -> gs_init_reply()).
init({PoolName, PoolSize}) ->
    %% wait for notifications from fox_connection_worker's that connections are ready
    {ok, #state{pool_name = PoolName, pool_size = PoolSize}}.


-spec(handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply()).
handle_call(get_channel, _From, #state{ready_channels = [], used_channels = []} = State) ->
    {reply, {error, no_connection}, State};

handle_call(get_channel, _From, #state{ready_channels = [], used_channels = UChannels} = State) ->
    [First | Rest] = lists:reverse(UChannels),
    {reply, {ok, First}, State#state{ready_channels = Rest, used_channels = [First]}};

handle_call(get_channel, _From, #state{ready_channels = [Next | RChannels], used_channels = UChannels} = State) ->
    {reply, {ok, Next}, State#state{ready_channels = RChannels, used_channels = [Next | UChannels]}};

handle_call(stop, _From, #state{ready_channels = RChannels, used_channels = UChannels} = State) ->
    lists:foreach(fun(Channel) ->
                          amqp_channel:close(Channel)
                  end, RChannels ++ UChannels),
    {stop, normal, ok, State#state{ready_channels = [], used_channels = []}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_cast(gs_request(), gs_state()) -> gs_cast_reply()).
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_info(gs_request(), gs_state()) -> gs_info_reply()).
handle_info(connections_ready, #state{pool_name = PoolName,
                                      pool_size = PoolSize,
                                      num_connections_ready = NumConnectionsReady} = State) ->
    case NumConnectionsReady + 1 of
        PoolSize ->
            {ok, Size} = application:get_env(fox, publish_pool_size),
            error_logger:info_msg("init publish channels pool ~p of size ~p", [PoolName, Size]),
            Channels = lists:map(fun(_Num) ->
                                         {ok, Pid} = fox:create_channel(PoolName),
                                         Pid
                                 end, lists:seq(1, Size)),
            {noreply, State#state{ready_channels = Channels, num_connections_ready = NumConnectionsReady + 1}};
        _ ->
            {noreply, State#state{num_connections_ready = NumConnectionsReady + 1}}
    end;

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec(terminate(terminate_reason(), gs_state()) -> ok).
terminate(_Reason, _State) ->
    ok.


-spec(code_change(term(), term(), term()) -> gs_code_change_reply()).
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.



%%% inner functions
