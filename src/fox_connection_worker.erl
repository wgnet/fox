-module(fox_connection_worker).
-behavior(gen_server).

-export([start_link/2, get_info/1, create_channel/1, subscribe/4, unsubscribe/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("stdlib/include/ms_transform.hrl").


-record(subscription, {
          ref :: reference(),
          channel_pid :: pid(),
          channel_ref :: reference(),
          consumer_pid :: pid(),
          consumer_ref :: reference(),
          consumer_module :: module(),
          consumer_args :: list(),
          queues :: [subscribe_queue()]
         }).


-record(state, {
          connection :: pid(),
          connection_ref :: reference(),
          params_network :: #amqp_params_network{},
          connect_callback :: fox_callback(),
          disconnect_callback :: fox_callback(),
          reconnect_attempt = 0 :: non_neg_integer(),
          subscriptions_ets :: ets:tid()
         }).


%%% module API

-spec start_link(#amqp_params_network{}, map()) -> gs_start_link_reply().
start_link(ConnectionParams, OtherParams) ->
    gen_server:start_link(?MODULE, {ConnectionParams, OtherParams}, []).


-spec get_info(pid()) -> {num_channel, integer()} | no_connection.
get_info(Pid) ->
    case gen_server:call(Pid, get_connection) of
        undefined -> no_connection;
        Connection -> hd(amqp_connection:info(Connection, [num_channels]))
    end.


-spec create_channel(pid()) -> {ok, pid()} | {error, term()}.
create_channel(Pid) ->
    gen_server:call(Pid, create_channel).


-spec subscribe(pid(), [subscribe_queue()], module(), list()) -> {ok, reference()} | {error, term()}.
subscribe(Pid, Queues, ConsumerModule, ConsumerArgs) ->
    gen_server:call(Pid, {subscribe, Queues, ConsumerModule, ConsumerArgs}).


-spec unsubscribe(pid(), reference()) -> ok | {error, term()}.
unsubscribe(Pid, SubscribeRef) ->
    gen_server:call(Pid, {unsubscribe, SubscribeRef}).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({ConnectionParams, OtherParams}) ->
    herd_rand:init_crypto(),
    TID = ets:new(subscriptions_ets, [{keypos, 2}]),
    self() ! connect,
    {ok, #state{
        params_network = ConnectionParams,
        connect_callback = maps:get(connect_callback, OtherParams, undefined),
        disconnect_callback = maps:get(disconnect_callback, OtherParams, undefined),
        subscriptions_ets = TID
    }}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(get_connection, _From, #state{connection = Connection} = State) ->
    {reply, Connection, State};

handle_call(create_channel, _From, #state{connection = Connection} = State) ->
    Reply = case Connection of
                undefined -> {error, no_connection};
                ConnectionPid -> amqp_connection:open_channel(ConnectionPid)
            end,
    {reply, Reply, State};

handle_call({subscribe, Queues, ConsumerModule, ConsumerArgs}, _From,
            #state{connection = Connection, subscriptions_ets = TID} = State) ->
    Ref = make_ref(),
    Sub = #subscription{ref = Ref,
                        consumer_module = ConsumerModule,
                        consumer_args = ConsumerArgs,
                        queues = Queues
                       },
    Reply = case Connection of
                undefined ->
                    ets:insert(TID, Sub),
                    {ok, Ref};
                _Pid ->
                    case do_subscription(Connection, Sub) of
                        {ok, Sub2} ->
                            ets:insert(TID, Sub2),
                            {ok, Ref};
                        {error, Reason} ->
                            {error, Reason}
                    end
            end,
    {reply, Reply, State};

handle_call({unsubscribe, Ref}, _From, #state{subscriptions_ets = TID} = State) ->
    case ets:lookup(TID, Ref) of
        [Subscription] -> close_subscription(Subscription),
                          ets:delete(TID, Ref),
                          {reply, ok, State};
        [] -> {reply, {error, subscription_not_found}, State}
    end;

handle_call(stop, _From, #state{connection = Connection,
                                connection_ref = Ref,
                                params_network = Params,
                                subscriptions_ets = TID} = State) ->
    error_logger:info_msg("fox_connection_worker close connection ~s", [fox_utils:params_network_to_str(Params)]),
    case Connection of
        undefined -> do_nothing;
        Pid ->
            lists:foreach(fun([Sub]) -> close_subscription(Sub) end, ets:match(TID, '$1')),
            erlang:demonitor(Ref, [flush]),
            fox_utils:close_connection(Pid)
    end,
    ets:delete(TID),
    {stop, normal, ok, State#state{connection = undefined, connection_ref = undefined}};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(connect, #state{connection = undefined, connection_ref = undefined,
                            params_network = Params, reconnect_attempt = Attempt,
                            connect_callback = Callback,
                            subscriptions_ets = TID} = State) ->
    case amqp_connection:start(Params) of
        {ok, Connection} ->
            Ref = erlang:monitor(process, Connection),
            error_logger:info_msg("fox_connection_worker connected to ~s",
                                  [fox_utils:params_network_to_str(Params)]),
            NewSubs = lists:map(fun([Sub]) ->
                                        close_subscription(Sub),
                                        {ok, Sub2} = do_subscription(Connection, Sub),
                                        Sub2
                                end,
                                ets:match(TID, '$1')),
            ets:delete_all_objects(TID),
            ets:insert(TID, NewSubs),
            fox_utils:call_callback(Callback),
            {noreply, State#state{connection = Connection, connection_ref = Ref, reconnect_attempt = 0}};
        {error, Reason} ->
            error_logger:error_msg("fox_connection_worker could not connect to ~s ~p",
                                   [fox_utils:params_network_to_str(Params), Reason]),
            {ok, MaxTimeout} = application:get_env(fox, max_reconnect_timeout),
            {ok, MinTimeout} = application:get_env(fox, min_reconnect_timeout),
            Timeout = herd_reconnect:exp_backoff(Attempt, MinTimeout, MaxTimeout),
            error_logger:warning_msg("fox_connection_worker reconnect after ~p attempt ~p", [Timeout, Attempt]),
            erlang:send_after(Timeout, self(), connect),
            {noreply, State#state{connection = undefined, connection_ref = undefined,
                                  reconnect_attempt = Attempt + 1}}
    end;

handle_info({'DOWN', Ref, process, Connection, Reason},
            #state{connection = Connection, connection_ref = Ref, disconnect_callback = Callback} = State) ->
    error_or_info(Reason,
                  "fox_connection_worker, connection is DOWN: ~p""fox_connection_worker, connection is DOWN: ~p",
                  [Reason]),
    self() ! connect,
    fox_utils:call_callback(Callback),
    {noreply, State#state{connection = undefined, connection_ref = undefined}};

handle_info({'DOWN', Ref, process, Pid, Reason}, #state{connection = Connection, subscriptions_ets = TID} = State) ->
    erlang:demonitor(Ref, [flush]),

    MS = ets:fun2ms(fun(#subscription{channel_pid = ChPid, consumer_pid = CoPid} = Sub)
                          when ChPid == Pid orelse CoPid == Pid ->
                            Sub
                    end),
    case ets:select(TID, MS) of
        [] -> do_nothing;
        [Sub] ->
            error_or_info(Reason,
                          "fox_connection_worker, channel or consumer ~p is DOWN: ~p",
                          [Pid, Reason]),
            close_subscription(Sub),
            case Connection of
                undefined -> do_nothing;
                _Pid ->
                    try
                        {ok, Sub2} = do_subscription(Connection, Sub),
                        ets:insert(TID, Sub2)
                    catch
                        E:R -> error_logger:error_msg("do_subscription~n~p:~p~n~p", [E, R, erlang:get_stacktrace()])
                    end
            end
    end,
    {noreply, State};


handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.


%% inner functions

-spec do_subscription(pid(), #subscription{}) -> {ok, #subscription{}} | {error, term()}.
do_subscription(Connection, #subscription{consumer_module = ConsumerModule, consumer_args = ConsumerArgs, queues = Queues} = Sub) ->
    case amqp_connection:open_channel(Connection) of
        {ok, ChannelPid} ->
            {ok, ConsumerPid} = fox_channel_sup:start_worker(ChannelPid, Queues, ConsumerModule, ConsumerArgs),
            ChannelRef = erlang:monitor(process, ChannelPid),
            ConsumerRef = erlang:monitor(process, ConsumerPid),
            Sub2 = Sub#subscription{channel_pid = ChannelPid,
                                    channel_ref = ChannelRef,
                                    consumer_pid = ConsumerPid,
                                    consumer_ref = ConsumerRef},
            {ok, Sub2};
        {error, Reason} ->
            {error, Reason}
    end.


-spec close_subscription(#subscription{}) -> #subscription{}.
close_subscription(#subscription{channel_pid = undefined, channel_ref = undefined,
                                 consumer_pid = undefined, consumer_ref = undefined} = Sub) ->
    Sub;
close_subscription(#subscription{channel_pid = ChannelPid, channel_ref = ChannelRef,
                                 consumer_pid = ConsumerPid, consumer_ref = ConsumerRef} = Sub) ->
    erlang:demonitor(ChannelRef, [flush]),
    erlang:demonitor(ConsumerRef, [flush]),
    fox_utils:close_consumer(ConsumerPid),
    fox_utils:close_channel(ChannelPid),
    Sub#subscription{channel_pid = undefined, channel_ref = undefined,
                     consumer_pid = undefined, consumer_ref = undefined}.


error_or_info(normal, ErrMsg, Params) ->
    error_logger:info_msg(ErrMsg, Params);

error_or_info(_, ErrMsg, Params) ->
    error_logger:error_msg(ErrMsg, Params).
