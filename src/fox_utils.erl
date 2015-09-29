-module(fox_utils).

-export([name_to_atom/1,
         map_to_params_network/1,
         params_network_to_str/1,
         validate_params_network_types/1,
         validate_consumer_behaviour/1,
         map_to_exchange_declare/1,
         map_to_exchange_delete/1,
         map_to_queue_declare/1,
         map_to_queue_delete/1,
         map_to_queue_bind/1,
         map_to_queue_unbind/1,
         map_to_basic_publish/1,
         map_to_pbasic/1,
         close_connection/1,
         close_channel/1
        ]).

-include("fox.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").


%%% module API

-spec name_to_atom(connection_name()) -> atom().
name_to_atom(Name) when is_binary(Name) ->
    name_to_atom(erlang:binary_to_atom(Name, utf8));
name_to_atom(Name) when is_list(Name) ->
    name_to_atom(list_to_atom(Name));
name_to_atom(Name) -> Name.


-spec map_to_params_network(map()) -> #amqp_params_network{}.
map_to_params_network(Params) when is_map(Params) ->
    #amqp_params_network{
       host = maps:get(host, Params),
       port = maps:get(port, Params),
       virtual_host = maps:get(virtual_host, Params),
       username = maps:get(username, Params),
       password = maps:get(password, Params),
       heartbeat = maps:get(heartbeat, Params, 10),
       connection_timeout = maps:get(connection_timeout, Params, 10),
       channel_max = maps:get(channel_max, Params, 0),
       frame_max = maps:get(frame_max, Params, 0),
       ssl_options = maps:get(ssl_options, Params, none),
       auth_mechanisms = maps:get(auth_mechanisms, Params,
                                  [fun amqp_auth_mechanisms:plain/3,
                                   fun amqp_auth_mechanisms:amqplain/3]),
       client_properties = maps:get(client_properties, Params, []),
       socket_options = maps:get(socket_options, Params, [])
      }.


-spec params_network_to_str(#amqp_params_network{}) -> iolist().
params_network_to_str(#amqp_params_network{host = Host,
                                           port = Port,
                                           virtual_host = VHost,
                                           username = Username}) ->
    io_lib:format("~s@~s:~p~s", [Username, Host, Port, VHost]).


-spec validate_params_network_types(#amqp_params_network{}) -> true | no_return().
validate_params_network_types(
  #amqp_params_network{
     host = Host,
     port = Port,
     virtual_host = VirtualHost,
     username = UserName,
     password = Password,
     heartbeat = Heartbeat,
     connection_timeout = Timeout,
     channel_max = ChannelMax,
     frame_max = FrameMax,
     ssl_options = SSL_Options,
     auth_mechanisms = AuthMechanisms,
     client_properties = ClientProperties,
     socket_options = SocketOptions
    }) ->
    if
        not is_list(Host) -> throw({invalid_amqp_params_network, "host should be string"});
        not is_integer(Port) -> throw({invalid_amqp_params_network, "port should be integer"});
        not is_binary(VirtualHost) -> throw({invalid_amqp_params_network, "virtual_host should be binary"});
        not is_binary(UserName) -> throw({invalid_amqp_params_network, "username should be binary"});
        not is_binary(Password) -> throw({invalid_amqp_params_network, "password should be binary"});
        not is_integer(Heartbeat) -> throw({invalid_amqp_params_network, "heartbeat should be integer"});
        not is_integer(Timeout) -> throw({invalid_amqp_params_network, "connection_timeout should be integer"});
        not is_integer(ChannelMax) -> throw({invalid_amqp_params_network, "channel_max should be integer"});
        not is_integer(FrameMax) -> throw({invalid_amqp_params_network, "frame_max should be integer"});
        not (SSL_Options == none orelse is_list(SSL_Options)) ->
            throw({invalid_amqp_params_network, "ssl_options should be list or none"});
        not is_list(AuthMechanisms) -> throw({invalid_amqp_params_network, "auth_mechanisms should be list"});
        not is_list(ClientProperties) -> throw({invalid_amqp_params_network, "client_properties should be list"});
        not is_list(SocketOptions) -> throw({invalid_amqp_params_network, "socket_options should be list"});
        true -> true
    end.


-spec validate_consumer_behaviour(module()) -> true | no_return().
validate_consumer_behaviour(Module) ->
    case code:is_loaded(Module) of
        {file, _} -> do_nothing;
        false -> code:load_file(Module)
    end,
    Callbacks = fox_channel_consumer:behaviour_info(callbacks),
    NotExported = lists:filter(fun({Fun, Arity}) ->
                                       not erlang:function_exported(Module, Fun, Arity)
                               end, Callbacks),
    case NotExported of
        [] -> true;
        _ -> throw({invalid_consumer_module, {should_be_exported, NotExported}})
    end.


-spec map_to_exchange_declare(map()) -> #'exchange.declare'{}.
map_to_exchange_declare(Params) ->
    #'exchange.declare'{
       ticket = maps:get(ticket, Params, 0),
       exchange = maps:get(exchange, Params, <<>>),
       type = maps:get(type, Params, <<"direct">>),
       passive = maps:get(passive, Params, false),
       durable = maps:get(durable, Params, false),
       auto_delete = maps:get(auto_delete, Params, false),
       internal = maps:get(internal, Params, false),
       nowait = maps:get(nowait, Params, false),
       arguments = maps:get(arguments, Params, [])
      }.


-spec map_to_exchange_delete(map()) -> #'exchange.delete'{}.
map_to_exchange_delete(Params) ->
    #'exchange.delete'{
       ticket = maps:get(ticket, Params, 0),
       exchange = maps:get(exchange, Params, <<>>),
       if_unused = maps:get(if_unused, Params, false),
       nowait = maps:get(nowait, Params, false)
      }.


-spec map_to_queue_declare(map()) -> #'queue.declare'{}.
map_to_queue_declare(Params) ->
    #'queue.declare'{
       ticket = maps:get(ticket, Params, 0),
       queue = maps:get(queue, Params, <<>>),
       passive = maps:get(passive, Params, false),
       durable = maps:get(durable, Params, false),
       exclusive = maps:get(exclusive, Params, false),
       auto_delete = maps:get(auto_delete, Params, false),
       nowait = maps:get(nowait, Params, false),
       arguments = maps:get(arguments, Params, [])
      }.


-spec map_to_queue_delete(map()) -> #'queue.delete'{}.
map_to_queue_delete(Params) ->
    #'queue.delete'{
       ticket = maps:get(ticket, Params, 0),
       queue = maps:get(queue, Params, <<>>),
       if_unused = maps:get(if_unused, Params, false),
       if_empty = maps:get(if_empty, Params, false),
       nowait = maps:get(nowait, Params, false)
      }.


-spec map_to_queue_bind(map()) -> #'queue.bind'{}.
map_to_queue_bind(Params) ->
    #'queue.bind'{
       ticket = maps:get(ticket, Params, 0),
       queue = maps:get(queue, Params, <<>>),
       exchange = maps:get(exchange, Params, <<>>),
       routing_key = maps:get(routing_key, Params, <<>>),
       nowait = maps:get(nowait, Params, false),
       arguments = maps:get(arguments, Params, [])
      }.


-spec map_to_queue_unbind(map()) -> #'queue.unbind'{}.
map_to_queue_unbind(Params) ->
    #'queue.unbind'{
       ticket = maps:get(ticket, Params, 0),
       queue = maps:get(queue, Params, <<>>),
       exchange = maps:get(exchange, Params, <<>>),
       routing_key = maps:get(routing_key, Params, <<>>),
       arguments = maps:get(arguments, Params, [])
      }.


-spec map_to_basic_publish(map()) -> #'basic.publish'{}.
map_to_basic_publish(Params) ->
    #'basic.publish'{
       ticket = maps:get(ticket, Params, 0),
       exchange = maps:get(exchange, Params, <<>>),
       routing_key = maps:get(routing_key, Params, <<>>),
       mandatory = maps:get(mandatory, Params, false),
       immediate = maps:get(immediate, Params, false)
      }.


-spec map_to_pbasic(map()) -> #'P_basic'{}.
map_to_pbasic(Params) ->
    #'P_basic'{
       content_type = maps:get(content_type, Params, undefined),
       content_encoding = maps:get(content_encoding, Params, undefined),
       headers = maps:get(headers, Params, undefined),
       delivery_mode = maps:get(delivery_mode, Params, undefined),
       priority = maps:get(priority, Params, undefined),
       correlation_id = maps:get(correlation_id, Params, undefined),
       reply_to = maps:get(reply_to, Params, undefined),
       expiration = maps:get(expiration, Params, undefined),
       message_id = maps:get(message_id, Params, undefined),
       timestamp = maps:get(timestamp, Params, undefined),
       type = maps:get(type, Params, undefined),
       user_id = maps:get(user_id, Params, undefined),
       app_id = maps:get(app_id, Params, undefined),
       cluster_id = maps:get(cluster_id, Params, undefined)
      }.


-spec close_connection(pid()) -> ok.
close_connection(Pid) ->
    try
        amqp_connection:close(Pid), ok
    catch
        %% connection may already be closed
        exit:{noproc, _} -> ok
    end.


-spec close_channel(pid()) -> ok.
close_channel(Pid) ->
    try
        amqp_channel:close(Pid), ok
    catch
        %% channel may already be closed
        exit:{noproc, _} -> ok
    end.
