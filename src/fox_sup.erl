-module(fox_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-include("otp_types.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->

    ConnectionPoolSup =
        {fox_conn_pool_sup,
         {fox_conn_pool_sup, start_link, []},
         permanent, 2000, supervisor,
         [fox_conn_pool_sup]},

    ChannelSup =
        {fox_consumer_sup,
         {fox_consumer_sup, start_link, []},
         permanent, 2000, supervisor,
         [fox_consumer_sup]},

    {ok, {{one_for_one, 10, 60}, [ConnectionPoolSup, ChannelSup]}}.
