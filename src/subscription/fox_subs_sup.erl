-module(fox_subs_sup).
-behaviour(supervisor).

-export([start_link/0, start_router/1, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec start_router(#subscription{}) -> startchild_ret().
start_router(Sub) ->
    supervisor:start_child(?MODULE, [Sub]).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    Worker = {fox_subs_router,
              {fox_subs_router, start_link, []},
              transient, 2000, worker,
              [fox_subs_router]},
    {ok, {{simple_one_for_one, 10, 60}, [Worker]}}.
