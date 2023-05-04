-module(fox_priv_utils).

-include("fox.hrl").

-export([reconnect/1, close_connection/1, close_channel/1, error_or_info/3]).


-spec reconnect(integer()) -> ok.
reconnect(Attempt) ->
    {ok, MaxTimeout} = application:get_env(fox, max_reconnect_timeout),
    {ok, MinTimeout} = application:get_env(fox, min_reconnect_timeout),
    Timeout = exp_backoff(Attempt, MinTimeout, MaxTimeout),
    erlang:send_after(Timeout, self(), connect),
    ok.


-spec close_connection(pid()) -> ok.
close_connection(Pid) ->
    try
        amqp_connection:close(Pid), ok
    catch
        exit:{noproc, _} -> ok; % connection may already be closed
        E:R -> error_logger:error_msg("can't close connection ~0p:~0p", [E, R])
    end.


-spec close_channel(pid()) -> ok.
close_channel(Pid) ->
    try
        amqp_channel:close(Pid), ok
    catch
        exit:{noproc, _} -> ok; % channel may already be closed
        E:R:StackTrace -> error_logger:error_msg("can't close channel ~0p:~0p ~0p", [E, R, StackTrace])
    end.


-spec error_or_info(atom(), iolist(), list()) -> ok.
error_or_info(normal, ErrMsg, Params) ->
    error_logger:info_msg(ErrMsg, Params);

error_or_info(_, ErrMsg, Params) ->
    error_logger:error_msg(ErrMsg, Params).


-spec exp_backoff(integer(), integer(), integer()) -> integer().
exp_backoff(Attempt, BaseTimeout, MaxTimeout) ->
    exp_backoff(Attempt, 10, BaseTimeout, MaxTimeout).


-spec exp_backoff(integer(), integer(), integer(), integer()) -> integer().
exp_backoff(Attempt, MaxAttempt, _BaseTimeout, MaxTimeout) when Attempt >= MaxAttempt ->
    Half = MaxTimeout div 2,
    Half + rand:uniform(Half);

exp_backoff(Attempt, _MaxAttempt, BaseTimeout, MaxTimeout) ->
    Timeout = min(erlang:round(math:pow(2, Attempt) * BaseTimeout), MaxTimeout),
    Half = Timeout div 2,
    Half + rand:uniform(Half).
