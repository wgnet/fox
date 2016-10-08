-module(fox_pub_channels_pool).
-behavior(gen_server).

-export([start_link/1, get_channel/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").

-record(state, {
          pool_name :: atom(),
          pool_size :: integer(),
          channels :: queue:queue()
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
    {ok, #state{pool_name = PoolName, pool_size = PoolSize, channels = queue:new()}}.


-spec(handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply()).
handle_call(get_channel, _From, #state{pool_name = PoolName, pool_size = PoolSize, channels = Channels} = State) ->
    NumChannels = queue:len(Channels),
    if
        NumChannels < PoolSize ->
            case fox:create_channel(PoolName) of
                {ok, Channel} ->
                    {reply, {ok, Channel}, State#state{channels = queue:in(Channel, Channels)}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        true ->
            {{value, Channel}, Channels2} = queue:out(Channels),
            case check_channel_alive(Channel, PoolName) of
                {ok, AliveChannel} ->
                    {reply, {ok, AliveChannel}, State#state{channels = queue:in(AliveChannel, Channels2)}};
                {error, Reason} ->
                    {reply, {error, Reason}, State#state{channels = Channels2}}
            end
    end;

handle_call(stop, _From, #state{channels = Channels} = State) ->
    lists:foreach(fun(Channel) ->
                          fox_utils:close_channel(Channel)
                  end, queue:to_list(Channels)),
    {stop, normal, ok, State#state{channels = queue:new()}};

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

check_channel_alive(Channel, PoolName) ->
    case erlang:is_process_alive(Channel) of
        true -> {ok, Channel};
        false -> fox:create_channel(PoolName)
    end.
