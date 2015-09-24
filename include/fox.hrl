-type(connection_name() :: binary() | string() | atom()).

-define(info(Str), error_logger:info_msg(Str)).
-define(info(Format, Params), error_logger:info_msg(Format, Params)).

-define(error(Str), error_logger:error_msg(Str)).
-define(error(Format, Params), error_logger:error_msg(Format, Params)).
