-module(fox_subs_worker).
-behavior(gen_server).

-export([start_link/1, connection_established/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").

-callback init(Channel :: pid(), Args :: list()) -> {ok, State :: term()}.
-callback handle(Msg :: term(), Channel :: pid(), State :: term()) -> {ok, State :: term()}.
-callback terminate(Channel :: pid(), State :: term()) -> ok.


%%% module API

-spec start_link(#subscription{}) -> gs_start_link_reply().
start_link(Subs) ->
    gen_server:start_link(?MODULE, Subs, []).


-spec connection_established(pid(), pid()) -> ok.
connection_established(Pid, Conn) ->
    gen_server:cast(Pid, {connection_established, Conn}).


-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init(Subs) ->
    put('$module', ?MODULE),
    {ok, Subs}.


-spec handle_call(gs_request(), gs_from(), gs_reply()) -> gs_call_reply().
handle_call(stop, _From,
    #subscription{
        channel = Channel,
        subs_module = Module,
        subs_state = SubsState,
        subs_tag = Tag}
        = State) ->
    fox_utils:channel_call(Channel, #'basic.cancel'{consumer_tag = Tag}),
    Module:terminate(Channel, SubsState),
    fox_priv_utils:close_channel(Channel),
    {stop, normal, ok, State};

handle_call(Any, _From, State) ->
    error_logger:error_msg("unknown call ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_cast(gs_request(), gs_state()) -> gs_cast_reply().
handle_cast({connection_established, Conn},
    #subscription{
        queue = Queue,
        subs_module = Module,
        subs_args = Args}
        = State) ->
    {ok, Channel} = amqp_connection:open_channel(Conn),
    {ok, SubsState} = Module:init(Channel, Args),
    BConsume = case Queue of
                   #'basic.consume'{} = B -> B;
                   QueueName when is_binary(QueueName) ->
                       #'basic.consume'{queue = QueueName}
               end,
    #'basic.consume_ok'{consumer_tag = Tag} =
        amqp_channel:subscribe(Channel, BConsume, self()),
    {noreply, State#subscription{channel = Channel, subs_state = SubsState, subs_tag = Tag}};


handle_cast(Any, State) ->
    error_logger:error_msg("unknown cast ~p in ~p ~n", [Any, ?MODULE]),
    {noreply, State}.


-spec handle_info(gs_request(), gs_state()) -> gs_info_reply().
handle_info(#'basic.consume_ok'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info({#'basic.deliver'{}, #amqp_msg{}} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info(#'basic.cancel'{} = Msg, State) ->
    {noreply, handle(Msg, State)};

handle_info(Request, State) ->
    error_logger:error_msg("unknown info ~p in ~p ~n", [Request, ?MODULE]),
    {noreply, State}.


-spec terminate(terminate_reason(), gs_state()) -> ok.
terminate(_Reason, _State) ->
    ok.


-spec code_change(term(), term(), term()) -> gs_code_change_reply().
code_change(_OldVersion, State, _Extra) ->
    {ok, State}.



handle(Msg,
    #subscription{
        channel = Channel,
        subs_module = Module,
        subs_state = SubsState}
        = State) ->
    {ok, SubsState2} = Module:handle(Msg, Channel, SubsState),
    State#subscription{subs_state = SubsState2}.
