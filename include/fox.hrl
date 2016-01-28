-include_lib("amqp_client/include/amqp_client.hrl").

-type(connection_name() :: binary() | string() | atom()).
-type(queue_name() :: binary()).
-type(subscribe_queue() :: queue_name() | #'basic.consume'{}).
