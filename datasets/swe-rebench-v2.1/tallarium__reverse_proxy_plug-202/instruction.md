Error callback can be simplified
It will be a breaking change, but there is no reason for the `opts[:error_callback]` to pass `{:error, error}` through from `response/3` - we should [HIDDEN] and pass `error` through to the callback instead.
