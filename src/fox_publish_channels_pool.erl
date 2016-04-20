-module(fox_publish_channels_pool).
-behavior(gen_server).

-export([start_link/1, get_channel/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").

-record(state, {
          pool_name :: atom(),
          pool_size :: integer(),
          num_channels = 0 :: integer(),
          ready_channels = [] :: [pid()],
          used_channels = [] :: [pid()]
         }).


%%% module API

-spec(start_link(atom()) -> gs_init_reply()).
start_link(PoolName) ->
    gen_server:start_link(?MODULE, PoolName, []).


-spec get_channel(pid()) -> {ok, pid()} | {error, no_connection}.
get_channel(Pid) ->
    gen_server:call(Pid, get_channel).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec(init(gs_args()) -> gs_init_reply()).
init(PoolName) ->
    {ok, PoolSize} = application:get_env(fox, publish_pool_size),
    error_logger:info_msg("init publish channels pool ~p of size ~p", [PoolName, PoolSize]),
    {ok, #state{pool_name = PoolName, pool_size = PoolSize, num_channels = 0}}.


-spec(handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply()).
handle_call(get_channel, _From,
    #state{pool_name = PoolName, pool_size = PoolSize, num_channels = NumChannels, used_channels = U} = State)
    when PoolSize > NumChannels ->
    case fox:create_channel(PoolName) of
        {ok, Pid} -> {reply, {ok, Pid}, State#state{used_channels = [Pid | U], num_channels = NumChannels + 1}};
        {error, Reason} -> {reply, {error, Reason}, State}
    end;

handle_call(get_channel, _From, #state{ready_channels = [], used_channels = U} = State) ->
    [First | Rest] = lists:reverse(U),
    {reply, {ok, First}, State#state{ready_channels = Rest, used_channels = [First]}};

handle_call(get_channel, _From, #state{ready_channels = [Next | R], used_channels = U} = State) ->
    {reply, {ok, Next}, State#state{ready_channels = R, used_channels = [Next | U]}};

handle_call(stop, _From, #state{ready_channels = R, used_channels = U} = State) ->
    lists:foreach(fun(Channel) ->
                          fox_utils:close_channel(Channel)
                  end, R ++ U),
    {stop, normal, ok, State#state{ready_channels = [], used_channels = [], num_channels = 0}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_cast(gs_request(), gs_state()) -> gs_cast_reply()).
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec(handle_info(gs_request(), gs_state()) -> gs_info_reply()).
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
