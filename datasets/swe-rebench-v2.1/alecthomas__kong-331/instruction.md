Optional arguments should not be allowed after repeated args
This makes no sense: `cmd <arg> ... [<last>]`. `<last>` will never be provided.
