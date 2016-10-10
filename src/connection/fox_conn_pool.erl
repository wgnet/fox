-module(fox_conn_pool).
-behavior(gen_server).

-export([start_link/3, get_conn_worker/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    conn_workers :: queue:queue()
}).


%%% module API

-spec start_link(atom(), #amqp_params_network{}, integer()) -> gs_start_link_reply().
start_link(PoolName, ConnectionParams, PoolSize) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:start_link({local, RegName}, ?MODULE, {PoolName, ConnectionParams, PoolSize}, []).


-spec get_conn_worker(atom()) -> pid().
get_conn_worker(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, get_conn_worker).


-spec stop(pid()) -> ok.
stop(_Pid) ->
    %% TODO
    %% gen_server:call(Pid, stop).
    ok.


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({PoolName, ConnectionParams, PoolSize}) ->
    put('$module', ?MODULE),
    Connections = [
        begin
            {ok, Pid} = fox_conn_sup:create_conn_worker(PoolName, Id, ConnectionParams),
            Pid
        end || Id <- lists:seq(1, PoolSize)],
    {ok, #state{conn_workers = queue:from_list(Connections)}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(get_conn_worker, _From, #state{conn_workers = Workers} = State) ->
    {{value, W}, Ws} = queue:out(Workers),
    Ws2 = queue:in(W, Ws),
    {reply, W, State#state{conn_workers = Ws2}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

