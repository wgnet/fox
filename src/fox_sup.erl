-module(fox_sup).
-behaviour(supervisor).

-export([start_link/0, start_pool/3, stop_pool/1, pool_exists/1, init/1]).
-include("otp_types.hrl").
-include("fox.hrl").

-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec start_pool(atom(), #amqp_params_network{}, integer()) -> startchild_ret().
start_pool(PoolName, ConnectionParams, PoolSize) ->
    Spec = {
        {fox_conn_pool_sup, PoolName},
        {fox_conn_pool_sup, start_link, [PoolName, ConnectionParams, PoolSize]},
        transient, 2000, supervisor,
        [fox_conn_pool_sup]
    },
    supervisor:start_child(?MODULE, Spec).


-spec stop_pool(atom()) -> ok.
stop_pool(PoolName) ->
    ok = supervisor:terminate_child(?MODULE, {fox_conn_pool_sup, PoolName}),
    ok = supervisor:delete_child(?MODULE, {fox_conn_pool_sup, PoolName}),
    ok.


-spec pool_exists(atom()) -> boolean().
pool_exists(PoolName) ->
    case supervisor:get_childspec(?MODULE, {fox_conn_pool_sup, PoolName}) of
        {ok, _} -> true;
        {error, _} -> false
    end.


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.
