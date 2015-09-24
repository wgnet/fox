-module(fox_channel_sup).
-behaviour(supervisor).

-export([start_link/0, start_channel/2, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec start_channel(pid(), integer()) -> ok.
start_channel(Connection, ChannelNumber) ->
    {ok, _} = supervisor:start_child(?MODULE, [Connection, ChannelNumber]),
    ok.


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    Worker = {fox_channel_worker,
              {fox_channel_worker, start_link, []},
              transient, 2000, worker,
              [fox_channel_worker]},
    {ok, {{simple_one_for_one, 10, 60}, [Worker]}}.
