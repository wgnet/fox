-module(fox_channel_consumer).
-behavior(gen_server).

-export([start_link/4, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-callback init(Channel :: pid(), Args :: list()) -> {ok, State :: term()}.
-callback handle(Msg :: term(), Channel :: pid(), State :: term()) -> {ok, State :: term()}.
-callback terminate(Channel :: pid(), State :: term()) -> ok.


-record(state, {channel_pid :: pid(),
                consumer :: module(),
                consumer_args :: list(),
                consumer_tags :: [binary()],
                consumer_queues :: [subscribe_queue()],
                consumer_state :: term()
               }).


%%% module API

-spec start_link(pid(), [subscribe_queue()], module(), list()) -> gs_start_link_reply().
start_link(ChannelPid, Queues, ConsumerModule, ConsumerModuleArgs) ->
    gen_server:start_link(?MODULE, {ChannelPid, Queues, ConsumerModule, ConsumerModuleArgs}, []).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({ChannelPid, Queues, ConsumerModule, ConsumerModuleArgs}) ->
    self() ! init,
    {ok, #state{channel_pid = ChannelPid, consumer = ConsumerModule,
                consumer_tags = [],
                consumer_queues = Queues,
                consumer_args = ConsumerModuleArgs}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #state{channel_pid = ChannelPid,
                                consumer = ConsumerModule,
                                consumer_tags = Tags,
                                consumer_state = CState} = State) ->
    %% unsubscribe
    lists:foreach(fun(Tag) ->
                          fox_utils:channel_call(ChannelPid, #'basic.cancel'{consumer_tag = Tag})
                  end, Tags),
    try
        ConsumerModule:terminate(ChannelPid, CState)
    catch
        T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:terminate~n~p:~p~nstacktrace: ~p",
                                      [ConsumerModule, T, E, erlang:get_stacktrace()])
    end,
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(#'basic.consume_ok'{consumer_tag = Tag}, #state{consumer_tags = Tags} = State) ->
    case lists:member(Tag, Tags) of
        true -> ok;
        false -> error_logger:error_msg("~p got basic_consume_ok with unknown tag ~p", [?MODULE, Tag])
    end,
    {noreply, State};

handle_info({#'basic.deliver'{consumer_tag = Tag}, #amqp_msg{}} = Data, #state{consumer_tags = Tags} = State) ->
    case lists:member(Tag, Tags) of
        true ->
            State2 = redirect_data_to_consumer(Data, State),
            {noreply, State2};
        false -> error_logger:error_msg("~p got basic.deliver with unknown tag ~p", [?MODULE, Tag]),
                 {noreply, State}
    end;

handle_info(#'basic.cancel'{consumer_tag = Tag} = Data, #state{consumer_tags = Tags} = State) ->
    case lists:member(Tag, Tags) of
        true ->
            State2 = redirect_data_to_consumer(Data, State),
            {noreply, State2};
        false -> error_logger:error_msg("~p got basic.cancel with unknown tag ~p", [?MODULE, Tag]),
                 {noreply, State}
    end;


handle_info(init, #state{channel_pid = ChannelPid,
                         consumer = ConsumerModule,
                         consumer_queues = Queues,
                         consumer_args = ConsumerArgs} = State) ->
    try
        {ok, CState} = ConsumerModule:init(ChannelPid, ConsumerArgs),
        Tags = lists:map(fun(Queue) -> % Queue is binary() or #'basic.consume{}
                                 BConsume = if
                                                is_binary(Queue) -> #'basic.consume'{queue = Queue};
                                                true -> Queue
                                            end,
                                 #'basic.consume_ok'{consumer_tag = Tag} =
                                     amqp_channel:subscribe(ChannelPid, BConsume, self()),
                                 Tag
                         end, Queues),
        {noreply, State#state{consumer_tags = Tags, consumer_state = CState}}
    catch
        T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:init~n~p:~p~nstacktrace: ~p",
                                      [ConsumerModule, T, E, erlang:get_stacktrace()]),
               {noreply, State}
    end;

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

redirect_data_to_consumer(Data, #state{channel_pid = ChannelPid,
                                       consumer = ConsumerModule,
                                       consumer_state = CState} = State) ->
    try
        {ok, CState2} = ConsumerModule:handle(Data, ChannelPid, CState),
        State#state{consumer_state = CState2}
    catch
        T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:handle~n~p:~p~nData:~p~nstacktrace: ~p",
                                      [ConsumerModule, T, E, Data, erlang:get_stacktrace()]),
               State
    end.
