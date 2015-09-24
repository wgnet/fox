-module(fox_utils).

-export([name_to_atom/1, params_network_to_str/1]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


%%% module API

-spec name_to_atom(connection_name()) -> atom().
name_to_atom(Name) when is_binary(Name) ->
    name_to_atom(erlang:binary_to_atom(Name, utf8));
name_to_atom(Name) when is_list(Name) ->
    name_to_atom(list_to_atom(Name));
name_to_atom(Name) -> Name.


-spec params_network_to_str(#amqp_params_network{}) -> iolist().
params_network_to_str(#amqp_params_network{host = Host,
                                           port = Port,
                                           virtual_host = VHost,
                                           username = Username}) ->
    io_lib:format("~s@~s:~p~s", [Username, Host, Port, VHost]).
