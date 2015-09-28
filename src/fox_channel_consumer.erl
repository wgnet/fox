-module(fox_channel_consumer).
-behavior(gen_server).

-export([start_link/3, behaviour_info/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-record(state, {channel_pid :: pid(),
                consumer :: module(),
                consumer_tag :: binary(),
                consumer_state :: term()
               }).


%%% module API

-spec start_link(pid(), module(), list()) -> gs_start_link_reply().
start_link(ChannelPid, ConsumerModule, ConsumerModuleArgs) ->
    gen_server:start_link(?MODULE, {ChannelPid, ConsumerModule, ConsumerModuleArgs}, []).


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
    {Tag2, State2} =
        case ConsumerModule:init(ChannelPid, ConsumerModuleArgs) of
            {ok, State} -> {undefined, State};
            {subscribe, Queue, State} ->
                Sub = #'basic.consume'{queue = Queue},
                #'basic.consume_ok'{consumer_tag = Tag} = amqp_channel:subscribe(ChannelPid, Sub, self()),
                {Tag, State}
        end,
    {ok, #state{channel_pid = ChannelPid, consumer = ConsumerModule,
                consumer_tag = Tag2, consumer_state = State2}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call({some, _Data}, _From, State) ->
    Reply = ok,
    {reply, Reply, State};

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
    {ok, CState2} = ConsumerModule:handle(Data, ChannelPid, CState),
    {noreply, State#state{consumer_state = CState2}};

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
