-module(fox_conn_sup).
-behaviour(supervisor).

-export([start_link/1, create_conn_worker/3, init/1]).

-include("otp_types.hrl").
-include("fox.hrl").


%% Module API

-spec start_link(atom()) -> {ok, pid()} | {error, term()}.
start_link(PoolName) ->
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_link({local, RegName}, ?MODULE, no_args).


-spec create_conn_worker(atom(), integer(), #amqp_params_network{}) -> startchild_ret().
create_conn_worker(PoolName, Id, ConnectionParams) ->
    Spec = {
        {fox_conn_worker, Id},
        {fox_conn_worker, start_link, [PoolName, Id, ConnectionParams]},
        transient, 2000, worker,
        [fox_conn_worker]
    },
    RegName = fox_utils:make_reg_name(?MODULE, PoolName),
    supervisor:start_child(RegName, Spec).


-spec init(gs_args()) -> sup_init_reply().
init(_Args) ->
    put('$module', ?MODULE),
    {ok, {{one_for_one, 10, 60}, []}}.


%%-spec create_channel(pid()) -> {ok, pid()} | {error, atom()}.
%%create_channel(SupPid) ->
%%    case get_less_busy_connection(SupPid) of
%%        {ok, Worker} -> fox_conn_worker:create_channel(Worker);
%%        {error, Reason} -> {error, Reason}
%%    end.
%%
%%
%%-spec subscribe(pid(), #subscription{}) -> {ok, reference()} | {error, term()}.
%%subscribe(SupPid, Sub) ->
%%    case get_less_busy_connection(SupPid) of
%%    {ok, Worker} ->
%%            fox_conn_worker:subscribe(Worker, Sub);
%%        {error, Reason} -> {error, Reason}
%%    end.
%%
%%
%%-spec unsubscribe(pid(), reference()) -> ok | {error, term()}.
%%unsubscribe(SupPid, Ref) ->
%%    Res = lists:map(fun({_, ChildPid, _, _}) ->
%%                            fox_conn_worker:unsubscribe(ChildPid, Ref)
%%                    end,
%%                    supervisor:which_children(SupPid)),
%%    case lists:member(ok, Res) of
%%        true -> ok;
%%        false -> {error, connection_not_found}
%%    end.
%%
%%
%%-spec stop(pid()) -> ok.
%%stop(SupPid) ->
%%    lists:foreach(fun({_, ChildPid, _, _}) ->
%%                          fox_conn_worker:stop(ChildPid)
%%                  end,
%%                  supervisor:which_children(SupPid)),
%%    ok.

