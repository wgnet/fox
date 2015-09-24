-module(fox_app).
-behaviour(application).

-export([start/0, start/2, stop/1]).


-spec(start() -> ok).
start() ->
    lager:start(),
    application:start(fox),
    ok.


-spec(start(term(), term()) -> {ok, pid()}).
start(_StartType, _StartArgs) ->
    lager:info("start some_app"),
    fox_sup:start_link().


-spec(stop(term()) -> ok).
stop(_State) ->
    ok.
