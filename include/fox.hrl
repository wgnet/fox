-include_lib("amqp_client/include/amqp_client.hrl").

-type(pool_name() :: binary() | string() | atom()).
-type(queue_name() :: binary()).
-type(subscribe_queue() :: queue_name() | #'basic.consume'{}).
-type(fox_callback() :: {pid(), atom()} | {atom(), atom()} | function() | undefined).

-record(subscription, {
    ref :: reference(),
    channel_pid :: pid(),
    subs_pid :: pid(),
    queues :: [subscribe_queue()],
    subs_module :: module(),
    subs_args :: list()
}).

