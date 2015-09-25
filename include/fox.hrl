-type(connection_name() :: binary() | string() | atom()).

-define(d(Str), error_logger:info_msg(Str)).
-define(d(Format, Params), error_logger:info_msg(Format, Params)).
