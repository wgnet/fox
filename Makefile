ERL_RUN_ARGS:=+pc unicode -pa ebin -config fox -boot start_sasl -s fox test_run

compile:
	rebar compile skip_deps=true

compile-all:
	rebar compile

get-deps:
	rebar get-deps

clean:
	rebar clean skip_deps=true
	rm -f erl_crash.dump
	rm test/*.beam

clean-all:
	rebar clean
	rm -f erl_crash.dump

tests: compile
	rebar eunit skip_deps=true
	rebar ct

run:
	ERL_LIBS=deps erl $(ERL_RUN_ARGS)

background:
	ERL_LIBS=deps erl -detached $(ERL_RUN_ARGS)

d:
	dialyzer --src -I include src

etags:
	etags src/*
