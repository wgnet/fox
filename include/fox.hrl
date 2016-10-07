-include_lib("amqp_client/include/amqp_client.hrl").

-type(pool_name() :: binary() | string() | atom()).
-type(queue_name() :: binary()).
-type(subscribe_queue() :: queue_name() | #'basic.consume'{}).

%% NOTE better use {Pid, Message} callback to avoid blocking fox_connection_worker or deadlock.
-type(fox_callback() :: {pid(), atom()} | {atom(), atom()} | function() | undefined).

-record(subscription, {
    ref :: reference(),
    channel_pid :: pid(),
    consumer_pid :: pid(),
    queues :: [subscribe_queue()],
    consumer_module :: module(),
    consumer_args :: list()
}).

