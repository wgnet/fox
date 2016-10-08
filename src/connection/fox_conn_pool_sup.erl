-module(fox_conn_pool_sup).
-behaviour(supervisor).

-export([start_link/0,
         init/1,
         start_pool/4, stop_pool/1,
         create_channel/1,
         get_publish_pool/1, get_publish_channel/1,
         subscribe/2, unsubscribe/2
        ]).

-include("otp_types.hrl").
-include("fox.hrl").


%% Module API

-spec(start_link() -> {ok, pid()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


-spec(init(gs_args()) -> sup_init_reply()).
init(_Args) ->
    {ok, {{one_for_one, 10, 60}, []}}.


-spec start_pool(atom(), #amqp_params_network{}, map(), integer()) -> ok | {error, term()}.
start_pool(PoolName, ConnectionParams, OtherParams, PoolSize) ->
    error_logger:info_msg("fox start pool ~p ~s of size ~p",
                          [PoolName, fox_utils:params_network_to_str(ConnectionParams), PoolSize]),
    PublishChannelsPool =
        {{fox_pub_channels_pool, PoolName},
         {fox_pub_channels_pool, start_link, [PoolName]},
         transient, 2000, worker,
         [fox_pub_channels_pool]},
    case supervisor:start_child(?MODULE, PublishChannelsPool) of
        {ok, _} ->
            ConnectionPoolSup = {{fox_conn_sup, PoolName},
                                 {fox_conn_sup, start_link, [ConnectionParams, OtherParams, PoolSize]},
                                 transient, 2000, supervisor,
                                 [fox_conn_sup]},
            case supervisor:start_child(?MODULE, ConnectionPoolSup) of
                {ok, _} -> ok;
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} -> {error, Reason}
    end.


-spec stop_pool(atom()) -> ok | {error, term()}.
stop_pool(PoolName) ->
    error_logger:info_msg("fox stop pool ~p", [PoolName]),
    ChildId1 = {fox_pub_channels_pool, PoolName},
    case find_child(ChildId1) of
        {ok, {ChildId1, ChildPid1, _, _}} ->
            fox_pub_channels_pool:stop(ChildPid1),
            ok = supervisor:terminate_child(?MODULE, ChildId1),
            supervisor:delete_child(?MODULE, ChildId1);
        {error, not_found} -> do_nothing
    end,
    ChildId2 = {fox_conn_sup, PoolName},
    case find_child(ChildId2) of
        {ok, {ChildId2, ChildPid2, _, _}} ->
            fox_conn_sup:stop(ChildPid2),
            ok = supervisor:terminate_child(?MODULE, ChildId2),
            supervisor:delete_child(?MODULE, ChildId2);
        {error, not_found} -> {error, pool_not_found}
    end.


-spec create_channel(atom()) -> {ok, pid()} | {error, atom()}.
create_channel(PoolName) ->
    ChildId = {fox_conn_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_conn_sup:create_channel(ChildPid);
        {error, not_found} -> {error, pool_not_found}
    end.


-spec get_publish_pool(atom()) -> {ok, pid()} | {error, atom()}.
get_publish_pool(PoolName) ->
    ChildId = {fox_pub_channels_pool, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} -> {ok, ChildPid};
        {error, not_found} -> {error, pool_not_found}
    end.


-spec get_publish_channel(atom()) -> {ok, pid()} | {error, atom()}.
get_publish_channel(PoolName) ->
    case get_publish_pool(PoolName) of
        {ok, PoolPid} -> fox_pub_channels_pool:get_channel(PoolPid);
        {error, Reason} -> {error, Reason}
    end.


-spec subscribe(atom(), #subscription{}) -> {ok, reference()} | {error, term()}.
subscribe(PoolName, Sub) ->
    ChildId = {fox_conn_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_conn_sup:subscribe(ChildPid, Sub);
        {error, not_found} -> {error, pool_not_found}
    end.


-spec unsubscribe(atom(), reference()) -> ok | {error, term()}.
unsubscribe(PoolName, Ref) ->
    ChildId = {fox_conn_sup, PoolName},
    case find_child(ChildId) of
        {ok, {ChildId, ChildPid, _, _}} ->
            fox_conn_sup:unsubscribe(ChildPid, Ref);
        {error, not_found} -> {error, pool_not_found}
    end.


%% Inner functions

-spec find_child(supervisor:child_id()) -> {ok, child_description()} | {error, not_found}.
find_child(ChildId) ->
    Res = lists:filter(fun({Id, _, _, _}) -> Id =:= ChildId end,
                       supervisor:which_children(?MODULE)),
    case Res of
        [Child] -> {ok, Child};
        [] -> {error, not_found}
    end.
