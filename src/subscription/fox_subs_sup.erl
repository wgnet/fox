-module(fox_subs_sup).
-behaviour(supervisor).

-export([start_link/1, start_subscriber/2, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_link({local, RegName}, ?MODULE, no_args).


-spec start_subscriber(atom(), #subscription{}) -> startchild_ret().
start_subscriber(PoolName, Sub) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_child(RegName, [Sub]).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    put('$module', ?MODULE),
    W = {
        fox_subs_worker,
        {fox_subs_worker, start_link, []},
        transient, 2000, worker,
        [fox_subs_worker]
    },
    {ok, {{simple_one_for_one, 10, 60}, [W]}}.
