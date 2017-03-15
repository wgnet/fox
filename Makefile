compile:
	rebar3 compile

eunit:
	rebar3 eunit

ct:
	rebar3 ct

tests: eunit ct

console:
	erl -pa _build/default/lib/*/ebin -s fox test_run

d:
	rebar3 dialyzer

clean:
	rebar3 clean

clean-all:
	rm -rf _build
	rm rebar.lock

