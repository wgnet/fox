-module(fox_connection_pool_sup).
-behaviour(supervisor).

-export([start_link/0, init/1, start_pool/2]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec start_pool(#amqp_params_network{}, integer()) -> ok.
start_pool(#amqp_params_network{host = Host,
                                port = Port,
                                virtual_host = VHost,
                                username = Username} = Params, PoolSize) ->
    ?info("fox start pool ~s@~s:~p~s of size ~p", [Username, Host, Port, VHost, PoolSize]),
    %% TODO run fox_connection_sup instead
    Spec = fun(Id) ->
                   {{some_worker, Id},
                    {some_worker, start_link, [Params]},
                    permanent,
                    2000,
                    worker,
                    [some_worker]}
           end,
    [supervisor:start_child(?MODULE, Spec(Id)) || Id <- lists:seq(1, PoolSize)],
    ok.


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.
