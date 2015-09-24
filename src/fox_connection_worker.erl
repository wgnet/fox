-module(fox_connection_worker).
-behavior(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("otp_types.hrl").
-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


-record(state, {
          connection :: pid(),
          params_network :: #amqp_params_network{},
          num_channels = 0 :: non_neg_integer(),
          reconnect_attempt = 0 :: non_neg_integer()
         }).


%%% module API

-spec start_link(term()) -> gs_start_link_reply().
start_link(Params) ->
    gen_server:start_link(?MODULE, Params, []).


%%% gen_server API

-spec init(gs_args()) -> gs_init_reply().
init(Params) ->
    herd_rand:init_crypto(),
    self() ! connect,
    {ok, #state{params_network = Params}}.


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
handle_info(connect, #state{params_network = Params, reconnect_attempt = Attempt} = State) ->
    case amqp_connection:start(Params) of
        {ok, Connection} ->
            %% TODO monitor connection
            error_logger:info_msg("fox_connection_worker connected to ~s",
                                  [fox_utils:params_network_to_str(Params)]),
            {noreply, State#state{connection = Connection, reconnect_attempt = 0}};
        {error, Reason} ->
            error_logger:error_msg("fox_connection_worker could not connect to ~s ~p",
                                   [fox_utils:params_network_to_str(Params), Reason]),
            {ok, MaxTimeout} = application:get_env(fox, max_reconnect_timeout),
            {ok, MinTimeout} = application:get_env(fox, min_reconnect_timeout),
            Timeout = herd_reconnect:exp_backoff(Attempt, MinTimeout, MaxTimeout),
            error_logger:warning_msg("fox_connection_worker reconnect after ~p attempt ~p", [Timeout, Attempt]),
            erlang:send_after(Timeout, self(), connect),
            {noreply, State#state{reconnect_attempt = Attempt + 1}}
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



%%% inner functions
