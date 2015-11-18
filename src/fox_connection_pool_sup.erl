-module(fox_connection_pool_sup).
-behaviour(supervisor).

-export([start_link/0,
         init/1,
         start_pool/3, stop_pool/1,
         create_channel/1,
         subscribe/3, unsubscribe/2
        ]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


%% Module API

-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.


-spec start_pool(atom(), #amqp_params_network{}, integer()) -> ok | {error, term()}.
start_pool(PoolName, Params, PoolSize) ->
    error_logger:info_msg("fox start pool ~p ~s of size ~p",
          [PoolName, fox_utils:params_network_to_str(Params), PoolSize]),
    ConnectionPoolSup = {{fox_connection_sup, PoolName},
                         {fox_connection_sup, start_link, [Params, PoolSize]},
                         transient, 2000, supervisor,
                         [fox_connection_sup]},
    case supervisor:start_child(?MODULE, ConnectionPoolSup) of
        {ok, _} -> ok;
        {error, Reason} -> {error, Reason}
    end.


-spec stop_pool(atom()) -> ok | {error, term()}.
stop_pool(PoolName) ->
    error_logger:info_msg("fox stop pool ~p", [PoolName]),
    ChildId = {fox_connection_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_connection_sup:stop(ChildPid),
            ok = supervisor:terminate_child(?MODULE, ChildId),
            supervisor:delete_child(?MODULE, ChildId);
        {error, not_found} -> {error, not_found}
    end.


-spec create_channel(atom()) -> {ok, pid()} | {error, term()}.
create_channel(PoolName) ->
    ChildId = {fox_connection_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_connection_sup:create_channel(ChildPid);
        {error, not_found} -> {error, not_found}
    end.


-spec subscribe(atom(), module(), list()) -> {ok, reference()} | {error, term()}.
subscribe(PoolName, ConsumerModule, ConsumerModuleArgs) ->
    ChildId = {fox_connection_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_connection_sup:subscribe(ChildPid, ConsumerModule, ConsumerModuleArgs);
        {error, not_found} -> {error, not_found}
    end.


-spec unsubscribe(atom(), pid()) -> ok | {error, term()}.
unsubscribe(PoolName, ChannelPid) ->
    ChildId = {fox_connection_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_connection_sup:unsubscribe(ChildPid, ChannelPid);
        {error, not_found} -> {error, not_found}
    end.


%% Inner functions

-spec find_child(term()) -> {ok, tuple()} | {error, not_found}.
find_child(ChildId) ->
    Res = lists:filter(fun({Id, _, _, _}) -> Id =:= ChildId end,
                       supervisor:which_children(?MODULE)),
    case Res of
        [Child] -> {ok, Child};
        [] -> {error, not_found}
    end.
