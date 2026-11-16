Extra newline printed when a flat subcommand has no arguments
When `flatten_help` is enabled and a subcommand doesn't have any arguments, an extra newline is printed like below:

```
Usage: cmd
       cmd foo [OPTIONS] [TO_VER]
       cmd bar

cmd foo:
Run foo
  -f, --from <FROM>     The version to upgrade from
  [TO_VER]           The version to upgrade to

cmd bar:
Run bar


After help:
...
```

It should instead be:

```
Usage: cmd
       cmd foo [OPTIONS] [TO_VER]
       cmd bar

cmd foo:
Run foo
  -f, --from <FROM>     The version to upgrade from
  [TO_VER]           The version to upgrade to

cmd bar:
Run bar

After help:
...
```
