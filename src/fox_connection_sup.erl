-module(fox_connection_sup).
-behaviour(supervisor).

-export([start_link/3, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


-spec(start_link(atom(), #amqp_params_network{}, integer()) -> {ok, pid()}).
start_link(PoolName, Params, PoolSize) ->
    supervisor:start_link({local, PoolName}, ?MODULE, {Params, PoolSize}).


-spec(init(gs_args()) -> sup_init_reply()).
init({#amqp_params_network{host = Host,
                           port = Port,
                           virtual_host = VHost,
                           username = Username} = Params, PoolSize}) ->
    ?info("fox start pool ~s@~s:~p~s of size ~p", [Username, Host, Port, VHost, PoolSize]),
    Spec = fun(Id) ->
                   {{some_worker, Id},
                    {some_worker, start_link, [Params]},
                    permanent,
                    2000,
                    worker,
                    [some_worker]}
           end,
    Childs = [Spec(Id) || Id <- lists:seq(1, PoolSize)],
    {ok, {{one_for_one, 10, 60}, Childs}}.
