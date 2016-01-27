%%
%% rabbit_common library define a lot of records.
%% But those record field types are not easy to reveal.
%% One need to look for them in sources.
%% Here I gather most important of those types & records.
%%

-type(resource_name() :: binary()).

-type(amqp_field_type() ::
      'longstr' | 'signedint' | 'decimal' | 'timestamp' |
      'table' | 'byte' | 'double' | 'float' | 'long' |
      'short' | 'bool' | 'binary' | 'void' | 'array').

-type(amqp_property_type() ::
      'shortstr' | 'longstr' | 'octet' | 'short' | 'long' |
      'longlong' | 'timestamp' | 'bit' | 'table').

-type(amqp_value() :: binary() |    % longstr
                      integer() |   % signedint
                      {non_neg_integer(), non_neg_integer()} | % decimal
                      amqp_table() |
                      amqp_array() |
                      byte() |      % byte
                      float() |     % double
                      integer() |   % long
                      integer() |   % short
                      boolean() |   % bool
                      binary() |    % binary
                      'undefined' | % void
                      non_neg_integer() % timestamp
     ).

-type(amqp_array() :: [{amqp_field_type(), amqp_value()}]).

-type(amqp_table() :: [{binary(), amqp_field_type(), amqp_value()}]).


%% exchange

-record('exchange.declare', {
          ticket = 0 :: non_neg_integer(),
          exchange :: resource_name(),
          type = <<"direct">> :: binary(),
          passive = false,
          durable = false,
          auto_delete = false,
          internal = false,
          nowait = false,
          arguments = [] :: amqp_table()
         }).

-record('exchange.delete', {
          ticket = 0 :: non_neg_integer(),
          exchange :: resource_name(),
          if_unused = false,
          nowait = false
         }).


%% queue

-record('queue.declare', {
          ticket = 0 :: non_neg_integer(),
          queue = <<"">> :: resource_name(),
          passive = false,
          durable = false,
          exclusive = false,
          auto_delete = false,
          nowait = false,
          arguments = [] :: amqp_table()
         }).

-record('queue.declare_ok', {
          queue :: resource_name(),
          message_count :: non_neg_integer(),
          consumer_count :: non_neg_integer()
         }).

-record('queue.bind', {
          ticket = 0 :: non_neg_integer(),
          queue = <<"">> :: resource_name(),
          exchange :: resource_name(),
          routing_key = <<"">> :: resource_name(),
          nowait = false,
          arguments = [] :: amqp_table()
         }).

-record('queue.delete', {
          ticket = 0 :: non_neg_integer(),
          queue = <<"">> :: resource_name(),
          if_unused = false,
          if_empty = false,
          nowait = false
         }).

-record('queue.delete_ok', {
          message_count :: non_neg_integer()
         }).

-record('queue.unbind', {
          ticket = 0 :: non_neg_integer(),
          queue = <<"">> :: resource_name(),
          exchange :: resource_name(),
          routing_key = <<"">> :: resource_name(),
          arguments = [] :: amqp_table()
         }).


%% basic

-record('basic.consume', {
          ticket = 0 :: non_neg_integer(),
          queue = <<"">> :: resource_name(),
          consumer_tag = <<"">> :: resource_name(),
          no_local = false,
          no_ack = false,
          exclusive = false,
          nowait = false,
          arguments = [] :: amqp_table()
         }).

-record('basic.consume_ok', {
          consumer_tag :: binary()
         }).

-record('basic.cancel', {
          consumer_tag :: binary(),
          nowait = false
         }).

-record('basic.cancel_ok', {
          consumer_tag :: binary()
         }).

-record('basic.publish', {
          ticket = 0 :: non_neg_integer(),
          exchange = <<"">> :: resource_name(),
          routing_key = <<"">> :: resource_name(),
          mandatory = false,
          immediate = false
         }).

-record('basic.deliver', {
          consumer_tag :: binary(),
          delivery_tag :: non_neg_integer(),
          redelivered = false,
          exchange :: resource_name(),
          routing_key :: resource_name()
         }).

-record('basic.ack', {
          delivery_tag = 0 :: non_neg_integer(),
          multiple = false
         }).

-record('basic.reject', {
          delivery_tag :: non_neg_integer(),
          requeue = true
         }).

-record('P_basic', {
          content_type     :: undefined | binary(),     % MIME content type
          content_encoding :: undefined | binary(),     % MIME content encoding
          headers          :: undefined | amqp_table(), % message header field table
          delivery_mode    :: undefined | 1 | 2,        % 1 or undefined -- non-persistent, 2 -- persistent
          priority         :: undefined | 0..9,         % message priority
          correlation_id   :: undefined | binary(),     % application correlation identifier
          reply_to         :: undefined | binary(),     % address to reply to
          expiration       :: undefined | binary(),     % message expiration specification
          message_id       :: undefined | binary(),     % application message identifier
          timestamp        :: undefined | non_neg_integer(), % message timestamp
          type             :: undefined | binary(),     % message type name
          user_id          :: undefined | binary(),     % creating user id
          app_id           :: undefined | binary(),     % creating application id
          cluster_id       :: undefined | binary()
         }).
