-module(fox_channel_consumer).
-behavior(gen_server).

-export([start_link/3, stop/1, behaviour_info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-record(state, {channel_pid :: pid(),
                consumer :: module(),
                consumer_args :: list(),
                consumer_tag :: binary(),
                consumer_state :: term()
               }).


%%% module API

-spec start_link(pid(), module(), list()) -> gs_start_link_reply().
start_link(ChannelPid, ConsumerModule, ConsumerModuleArgs) ->
    gen_server:start_link(?MODULE, {ChannelPid, ConsumerModule, ConsumerModuleArgs}, []).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


-spec behaviour_info(term()) -> term().
behaviour_info(callbacks) ->
    [{init, 2},
     {handle, 3},
     {terminate, 2}];
behaviour_info(_) ->
    undefined.


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({ChannelPid, ConsumerModule, ConsumerModuleArgs}) ->
    self() ! init,
    {ok, #state{channel_pid = ChannelPid, consumer = ConsumerModule,
                consumer_args = ConsumerModuleArgs}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #state{channel_pid = ChannelPid,
                                consumer = ConsumerModule,
                                consumer_state = CState} = State) ->
    try
        ConsumerModule:terminate(ChannelPid, CState)
    catch
        T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:terminate~n~p:~p",
                                      [ConsumerModule, T, E])
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
handle_info(#'basic.consume_ok'{consumer_tag = Tag}, #state{consumer_tag = Tag} = State) ->
    {noreply, State};

handle_info({#'basic.deliver'{consumer_tag = Tag}, #amqp_msg{}} = Data,
            #state{channel_pid = ChannelPid, consumer = ConsumerModule,
                   consumer_tag = Tag, consumer_state = CState} = State) ->
    {ok, CState2} =
        try
            ConsumerModule:handle(Data, ChannelPid, CState)
        catch
            T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:handle~n~p:~p~nData:~p",
                                          [ConsumerModule, T, E, Data]),
                   {ok, CState}
        end,
    {noreply, State#state{consumer_state = CState2}};

handle_info(init, #state{channel_pid = ChannelPid,
                         consumer = ConsumerModule,
                         consumer_args = ConsumerArgs} = State) ->
    {Tag2, CState2} =
        try ConsumerModule:init(ChannelPid, ConsumerArgs) of
            {ok, CState} -> {undefined, CState};
            {subscribe, Queue, CState} ->
                Sub = #'basic.consume'{queue = Queue},
                #'basic.consume_ok'{consumer_tag = Tag} = amqp_channel:subscribe(ChannelPid, Sub, self()),
                {Tag, CState}
        catch
            T:E -> error_logger:error_msg("fox_channel_consumer error in ~p:init~n~p:~p",
                                          [ConsumerModule, T, E]),
                   {undefined, undefined}
        end,
    {noreply, State#state{consumer_tag = Tag2, consumer_state = CState2}};

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.



%%% inner functions
