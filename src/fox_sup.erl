-module(fox_sup).
-behaviour(supervisor).

-export([start_link/0, start_pool/3, stop_pool/1, init/1]).
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
        permanent, 2000, supervisor,
        [fox_conn_pool_sup]
    },
    supervisor:start_child(?MODULE, Spec).


-spec stop_pool(atom()) -> ok | {error, term()}.
stop_pool(_PoolName) ->
    %% TODO
    ok.


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.
