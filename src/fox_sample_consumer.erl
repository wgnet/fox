-module(fox_sample_consumer).
-behaviour(amqp_gen_consumer).

-export([init/1,
         handle_consume/3, handle_consume_ok/3,
         handle_cancel/2, handle_cancel_ok/3,
         handle_server_cancel/2,
         handle_deliver/3, handle_deliver/4,
         handle_call/3,
         handle_info/2,
         terminate/2
        ]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


-type(state() :: term()).
-type(reason() :: term()).
-type(ok_error() :: {ok, state()} | {error, reason(), state()}).


%%% module API

-spec init(term()) -> {ok, state()} | {stop, reason()} | ignore.
init(Args) ->
    ?d("fox_sample_consumer:init ~p", [Args]),
    {ok, []}.


-spec handle_consume(#'basic.consume'{}, pid(), state()) -> ok_error().
handle_consume(_Consume, _Sender, State) ->
    {ok, State}.


-spec handle_consume_ok(#'basic.consume_ok'{}, #'basic.consume'{}, state()) -> ok_error().
handle_consume_ok(_ConsumeOk, _Consume, State) ->
    {ok, State}.


-spec handle_cancel(#'basic.cancel'{}, state()) -> ok_error().
handle_cancel(_Cancel, State) ->
    {ok, State}.


-spec handle_cancel_ok(#'basic.cancel_ok'{}, #'basic.cancel'{}, state()) -> ok_error().
handle_cancel_ok(_CancelOk, _Cancel, State) ->
    {ok, State}.


-spec handle_server_cancel(#'basic.cancel'{}, state()) -> ok_error().
handle_server_cancel(_Cancel, State) ->
    {ok, State}.


-spec handle_deliver(#'basic.deliver'{}, #amqp_msg{}, state()) -> ok_error().
handle_deliver(_Deliver, _Message, State) ->
    {ok, State}.


-spec handle_deliver(#'basic.deliver'{}, #amqp_msg{}, {pid(), pid(), pid()}, state()) -> ok_error().
handle_deliver(_Deliver, _Message, _DeliveryCtx, State) ->
    {ok, State}.


-spec handle_call(any(), any(), state()) -> {reply, any, state()} | {noreply, state()} | {error, reason(), state()}.
handle_call(_Msg, _From, State) ->
    {reply, 1, State}.


-spec handle_info(any(), state()) -> ok_error().
handle_info(_Info, State) ->
    {ok, State}.


-spec terminate(any(), state()) -> any().
terminate(_Reason, State) ->
    State.
