-module(fox_conn_sup).
-behaviour(supervisor).

-export([start_link/1, create_conn_worker/3, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


%% Module API

-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_link({local, RegName}, ?MODULE, no_args).


-spec create_conn_worker(atom(), integer(), #amqp_params_network{}) -> startchild_ret().
create_conn_worker(PoolName, Id, ConnectionParams) ->
    Spec = {
        {fox_conn_worker, Id},
        {fox_conn_worker, start_link, [PoolName, Id, ConnectionParams]},
        transient, 2000, worker,
        [fox_conn_worker]
    },
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_child(RegName, Spec).


-spec init(gs_args()) -> sup_init_reply().
init(_Args) ->
    put('$module', ?MODULE),
    {ok, {{one_for_one, 10, 60}, []}}.


