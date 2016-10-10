-module(fox_subs_sup).
-behaviour(supervisor).

-export([start_link/1, start_router/2, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_link({local, RegName}, ?MODULE, no_args).


-spec start_router(atom(), integer()) -> startchild_ret().
start_router(PoolName, Id) ->
    S = {
        {fox_subs_router, PoolName, Id},
        {fox_subs_router, start_link, []},
        transient, 2000, worker,
        [fox_subs_router]
    },
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_child(RegName, S).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    put('$module', ?MODULE),
    {ok, {{one_for_one, 10, 60}, []}}.
