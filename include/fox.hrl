-include_lib("amqp_client/include/amqp_client.hrl").

-type pool_name() :: binary() | string() | atom().
-type queue_name() :: binary().
-type subscribe_queue() :: queue_name() | #'basic.consume'{}.

-record(conn_worker_state, {
    connection :: pid() | undefined,
    connection_ref :: reference() | undefined,
    connection_params :: #amqp_params_network{},
    reconnect_attempt = 0 :: non_neg_integer(),
    subscribers = [] :: [{pid(), reference()}],
    registered_name :: atom()
}).

-record(subscription, {
    ref :: reference(),
    pool_name :: atom(),
    connection :: pid() | undefined,
    conn_worker :: pid(),
    basic_consume :: #'basic.consume'{},
    subs_module :: module(),
    subs_args :: list(),
    channel :: pid() | undefined,
    channel_ref :: reference() | undefined,
    subs_state :: term(),
    subs_tag :: binary() | undefined
}).

-record(subs_meta, {
    ref :: reference(),
    conn_worker :: pid(),
    subs_worker :: pid()
}).
