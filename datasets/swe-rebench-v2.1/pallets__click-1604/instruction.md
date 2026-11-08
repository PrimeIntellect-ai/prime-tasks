Can't mix nargs=-1 with envvar
`@click.argument(name, nargs=2, envvar=NAME)`

Works as expected. If you set `NAME="a b"` and run your command `name` in the called function will be a tuple of `('a', 'b')`.

`@click.argument(name, nargs=-1, envvar=NAME)`

on the other hand doesn't work as expected. If you call it in the same exact way, `name` will be set to the empty tuple.
