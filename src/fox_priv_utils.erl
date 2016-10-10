-module(fox_priv_utils).

-include("fox.hrl").

-export([reconnect/1, close_connection/1, close_channel/1, close_subs/1, error_or_info/3]).


-spec reconnect(integer()) -> ok.
reconnect(Attempt) ->
    {ok, MaxTimeout} = application:get_env(fox, max_reconnect_timeout),
    {ok, MinTimeout} = application:get_env(fox, min_reconnect_timeout),
    Timeout = herd_reconnect:exp_backoff(Attempt, MinTimeout, MaxTimeout),
    erlang:send_after(Timeout, self(), connect),
    ok.


-spec close_connection(pid()) -> ok.
close_connection(Pid) ->
    try
        amqp_connection:close(Pid), ok
    catch
        exit:{noproc, _} -> ok; % connection may already be closed
        E:R -> error_logger:error_msg("can't close connection~n~p:~p", [E, R])
    end.


-spec close_channel(pid()) -> ok.
close_channel(Pid) ->
    try
        amqp_channel:close(Pid), ok
    catch
        exit:{noproc, _} -> ok; % channel may already be closed
        E:R -> error_logger:error_msg("can't close channel~n~p:~p~n~p", [E, R, erlang:get_stacktrace()])
    end.


-spec close_subs(pid()) -> ok.
close_subs(Pid) ->
    try
        fox_subs_router:stop(Pid), ok
    catch
        exit:{noproc, _} -> ok; % subscription may already be closed
        E:R -> error_logger:error_msg("can't close subscription~n~p:~p~n~p", [E, R, erlang:get_stacktrace()])
    end.


-spec error_or_info(atom(), iolist(), list()) -> ok.
error_or_info(normal, ErrMsg, Params) ->
    error_logger:info_msg(ErrMsg, Params);

error_or_info(_, ErrMsg, Params) ->
    error_logger:error_msg(ErrMsg, Params).

