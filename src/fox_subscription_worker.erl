-module(fox_subscription_worker).
-behavior(gen_server).

-export([start_link/3, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-callback init(Channel :: pid(), Args :: list()) -> {ok, State :: term()}.
-callback handle(Msg :: term(), Channel :: pid(), State :: term()) -> {ok, State :: term()}.
-callback terminate(Channel :: pid(), State :: term()) -> ok.


-record(state, {
    channel :: pid(),
    consumer :: module(),
    consumer_state :: term()
}).


%%% module API

-spec start_link(pid(), module(), list()) -> gs_start_link_reply().
start_link(Channel, ConsumerModule, ConsumerArgs) ->
    gen_server:start_link(?MODULE, {Channel, ConsumerModule, ConsumerArgs}, []).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init({Channel, ConsumerModule, ConsumerArgs}) ->
    {ok, CState} = ConsumerModule:init(Channel, ConsumerArgs),
    {ok, #state{channel = Channel, consumer = ConsumerModule, consumer_state = CState}}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From, #state{channel = Channel, consumer = ConsumerModule, consumer_state = CState} = State) ->
    ConsumerModule:terminate(Channel, CState),
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(Msg, #state{channel = Channel, consumer = Module, consumer_state = CState} = State) ->
    {ok, CState2} = Module:handle(Msg, Channel, CState),
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

