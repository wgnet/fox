-module(fox_conn_pool).
-behavior(gen_server).

-export([
    start_link/3,
    get_conn_worker/1,
    save_subs_meta/2,
    get_subs_meta/2,
    remove_subs_meta/2,
    stop/1
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-record(state, {
    conn_workers :: queue:queue(),
    subscriptions :: map()
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


-spec save_subs_meta(atom(), #subs_meta{}) -> ok.
save_subs_meta(PoolName, SubsMeta) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, {save_subs_meta, SubsMeta}).


-spec get_subs_meta(atom(), reference()) -> #subs_meta{} | not_found.
get_subs_meta(PoolName, Ref) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, {get_subs_meta, Ref}).


-spec remove_subs_meta(atom(), reference()) -> ok.
remove_subs_meta(PoolName, Ref) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:cast(RegName, {remove_subs_meta, Ref}).


-spec stop(atom()) -> [#subs_meta{}].
stop(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    gen_server:call(RegName, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({PoolName, ConnectionParams, PoolSize}) ->
    put('$module', ?MODULE),
    Connections = [
        begin
            {ok, Pid} = fox_conn_sup:create_conn_worker(PoolName, Id, ConnectionParams),
            Pid
        end || Id <- lists:seq(1, PoolSize)],
    {ok, #state{conn_workers = queue:from_list(Connections), subscriptions = #{}}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(get_conn_worker, _From, #state{conn_workers = Workers} = State) ->
    {{value, W}, Ws} = queue:out(Workers),
    Ws2 = queue:in(W, Ws),
    {reply, W, State#state{conn_workers = Ws2}};

handle_call({save_subs_meta, SubsMeta}, _From, #state{subscriptions = SubsMap} = State) ->
    #subs_meta{ref = Ref} = SubsMeta,
    SubsMap2 = SubsMap#{Ref => SubsMeta},
    {reply, ok, State#state{subscriptions = SubsMap2}};

handle_call({get_subs_meta, Ref}, _From, #state{subscriptions = SubsMap} = State) ->
    Reply = case maps:find(Ref, SubsMap) of
        {ok, SubsMeta} -> SubsMeta;
        error -> not_found
    end,
    {reply, Reply, State};

handle_call(stop, _From, #state{subscriptions = SubsMap} = State) ->
    Reply = maps:values(SubsMap),
    {stop, normal, Reply, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({remove_subs_meta, Ref}, #state{subscriptions = SubsMap} = State) ->
    SubsMap2 = maps:remove(Ref, SubsMap),
    {noreply, State#state{subscriptions = SubsMap2}};

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

