-module(fox_utils).

-export([name_to_atom/1,
         make_reg_name/2,
         map_to_params_network/1,
         params_network_to_str/1,
         validate_params_network_types/1,
         map_to_exchange_declare/1,
         map_to_exchange_delete/1,
         map_to_queue_declare/1,
         map_to_queue_delete/1,
         map_to_queue_bind/1,
         map_to_queue_unbind/1,
         map_to_basic_publish/1,
         map_to_pbasic/1,
         map_to_basic_qos/1,
         channel_call/2, channel_call/3,
         channel_cast/2, channel_cast/3
        ]).

-include("fox.hrl").


%%% module API

-spec name_to_atom(pool_name()) -> atom().
name_to_atom(Name) when is_binary(Name) -> erlang:binary_to_atom(Name, utf8);
name_to_atom(Name) when is_list(Name) -> list_to_atom(Name);
name_to_atom(Name) when is_atom(Name) -> Name.


-spec make_reg_name(atom(), atom() | string() | integer()) -> atom().
make_reg_name(Name, Suffix) when is_integer(Suffix) ->
    make_reg_name(Name, integer_to_list(Suffix));
make_reg_name(Name, Suffix) when is_atom(Suffix) ->
    make_reg_name(Name, atom_to_list(Suffix));
make_reg_name(Name, Suffix) when is_list(Suffix) ->
    list_to_atom(
        lists:flatten([atom_to_list(Name), "/", Suffix])
    ).


-spec map_to_params_network(#amqp_params_network{} | map()) -> #amqp_params_network{}.
map_to_params_network(#amqp_params_network{} = P) -> P;
map_to_params_network(Params) when is_map(Params) ->
    #amqp_params_network{
        username = maps:get(username, Params, <<"guest">>),
        password = maps:get(password, Params, <<"guest">>),
        virtual_host = maps:get(virtual_host, Params, <<"/">>),
        host = maps:get(host, Params, "localhost"),
        port = maps:get(port, Params, undefined),
        channel_max = maps:get(channel_max, Params, 0),
        frame_max = maps:get(frame_max, Params, 0),
        heartbeat = maps:get(heartbeat, Params, 0), % seconds
        connection_timeout = maps:get(connection_timeout, Params, 10000), % milliseconds
        ssl_options = maps:get(ssl_options, Params, none),
        auth_mechanisms = maps:get(auth_mechanisms, Params,
            [fun amqp_auth_mechanisms:plain/3, fun amqp_auth_mechanisms:amqplain/3]),
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


-spec map_to_basic_qos(map()) -> #'basic.qos'{}.
map_to_basic_qos(Params) ->
    #'basic.qos'{
        prefetch_size = maps:get(prefetch_size, Params, 0),
        prefetch_count = maps:get(prefetch_count, Params, 0),
        global = maps:get(global, Params, false)
    }.


-spec channel_call(pid(), term()) -> ok | {error, atom()} | term().
channel_call(ChannelPid, Method) ->
    channel_call(ChannelPid, Method, none).


-spec channel_call(pid(), term(), term()) -> ok | {error, atom()} | term().
channel_call(ChannelPid, Method, Content) ->
    try amqp_channel:call(ChannelPid, Method, Content) of
        ok -> ok;
        blocked -> {error, blocked}; % server has throttled the client for flow control reasons
        closing -> {error, closing}; % channel is in the process of shutting down
        Reply -> Reply % #'exchange.declare_ok'{}, #'queue.bind_ok'{} etc
    catch
        exit:{noproc, _} -> {error, invalid_channel};
        exit:{{shutdown, Reason}, _} -> {error, {channel_closed, Reason}}
    end.


-spec channel_cast(pid(), term()) -> ok | {error, invalid_channel}.
channel_cast(ChannelPid, Method) ->
    channel_cast(ChannelPid, Method, none).


-spec channel_cast(pid(), term(), term()) -> ok | {error, invalid_channel}.
channel_cast(ChannelPid, Method, Content) ->
    try
        amqp_channel:cast(ChannelPid, Method, Content)
    catch
        exit:{noproc, _} -> {error, invalid_channel}
    end.


