show_default in group's context_settings not propagated to subcommands
### Expected Behavior

#1018 and #1225 seems to have fixed supporting a global `show_default` option via context settings, but in Click 7.1.2, it doesn't cover my use case yet.

I thought the following should work with 7.1+:

```python
import click

@click.group(context_settings={
    'show_default': True,
    'help_option_names': ['-x', '--xhelp'],
})
@click.pass_context
def main(ctx):
    print('==== main ====')
    print(ctx.show_default)
    print(ctx.help_option_names)

@main.command()
@click.option('-v', '--value', type=int, default=123, help='some value')
@click.pass_context
def do(ctx, value):
    print('==== do ====')
    print(ctx.show_default)
    print(ctx.help_option_names)
    print('----')
    print(value)

main()
```

```console
$ python test-click.py -x
Usage: test-click.py [OPTIONS] COMMAND [ARGS]...

Options:
  -x, --xhelp  Show this message and exit.  [default: False]

Commands:
  do

$ python test-click.py do -x
==== main ====
True
['-x', '--xhelp']
Usage: test-click.py do [OPTIONS]

Options:
  -v, --value INTEGER  some value  [default: 123]
  -x, --xhelp          Show this message and exit.

$ python test-click.py do
==== main ====
True
['-x', '--xhelp']
==== do ====
True
['-x', '--xhelp']
----
123
```

### Actual Behavior

But the current implementation seems to loose the value of `show_default` when "going into" subcommands.

```console
$ python test-click.py -x
Usage: test-click.py [OPTIONS] COMMAND [ARGS]...

Options:
  -x, --xhelp  Show this message and exit.  [default: False]

Commands:
  do

$ python test-click.py do -x
==== main ====
True
['-x', '--xhelp']
Usage: test-click.py do [OPTIONS]

Options:
  -v, --value INTEGER  some value
  -x, --xhelp          Show this message and exit.

$ python test-click.py do
==== main ====
True
['-x', '--xhelp']
==== do ====
None
['-x', '--xhelp']
----
123
```

### Environment

* Python version: 3.8.3
* Click version: 7.1.2
