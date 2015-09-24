-module(fox_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-include("otp_types.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    RestartStrategy = one_for_one, % one_for_one | one_for_all | rest_for_one
    Intensity = 10, %% max restarts
    Period = 60, %% in period of time
    SupervisorSpecification = {RestartStrategy, Intensity, Period},

    Restart = permanent, % permanent | transient | temporary
    Shutdown = 2000, % milliseconds | brutal_kill | infinity

    ChildSpecifications =
        [
         {some_worker,
          {some_worker, start_link, []},
          Restart,
          Shutdown,
          worker,
          [some_worker]}
        ],
    {ok, {SupervisorSpecification, ChildSpecifications}}.
