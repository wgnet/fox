-include_lib("amqp_client/include/amqp_client.hrl").

-type(pool_name() :: binary() | string() | atom()).
-type(queue_name() :: binary()).
-type(subscribe_queue() :: queue_name() | #'basic.consume'{}).

-record(subscription, {
    ref :: reference(),
    queue :: subscribe_queue(),
    subs_module :: module(),
    subs_args :: list()
}).

