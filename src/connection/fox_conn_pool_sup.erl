-module(fox_conn_pool_sup).
-behaviour(supervisor).

-export([start_link/3, stop/1, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


%% Module API

-spec start_link(atom(), #amqp_params_network{}, integer()) -> ok | {error, term()}.
start_link(PoolName, ConnectionParams, PoolSize) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_link({local, RegName}, ?MODULE, {PoolName, ConnectionParams, PoolSize}).


-spec stop(atom()) -> ok | {error, term()}.
stop(PoolName) ->
    error_logger:info_msg("fox stop pool ~p", [PoolName]),
    %% TODO
    ok.


-spec(init(gs_args()) -> sup_init_reply()).
init({PoolName, ConnectionParams, PoolSize}) ->
    put('$module', ?MODULE),
    SubsPoolSize =
        if
            PoolSize > 1 -> PoolSize - 1;
            true -> 1
        end,
    Childs = [
        {
            {fox_conn_sup, PoolName},
            {fox_conn_sup, start_link, [PoolName]},
            permanent, 2000, supervisor,
            [fox_conn_sup]
        },
        {
            {fox_subs_sup, PoolName},
            {fox_subs_sup, start_link, [PoolName]},
            permanent, 2000, supervisor,
            [fox_subs_sup]
        },
        {
            {fox_conn_pool, PoolName},
            {fox_conn_pool, start_link, [PoolName, ConnectionParams, SubsPoolSize]},
            permanent, 2000, worker,
            [fox_conn_pool]
        },
        {
            {fox_pub_pool, PoolName},
            {fox_pub_pool, start_link, [PoolName, ConnectionParams]},
            transient, 2000, worker,
            [fox_pub_pool]
        }
    ],
    {ok, {{rest_for_one, 10, 60}, Childs}}.
