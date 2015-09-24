-module(fox_connection_pool_sup).
-behaviour(supervisor).

-export([start_link/0, init/1, start_pool/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec start_pool(atom(), #amqp_params_network{}, integer()) -> ok.
start_pool(PoolName, Params, PoolSize) ->
    ConnectionPoolSup = {{fox_connection_sup, PoolName},
                         {fox_connection_sup, start_link, [PoolName, Params, PoolSize]},
                         permanent, 2000, supervisor,
                         [fox_connection_sup]},
    supervisor:start_child(?MODULE, ConnectionPoolSup),
    ok.


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.
