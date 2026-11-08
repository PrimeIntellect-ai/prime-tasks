Required arguments are omitted from command help synopsis
I have a `@click.group` that requires an argument.

The help text of the group itself correctly says `Usage: p.py [OPTIONS] NAME COMMAND [ARGS]...`. However, the help text of the subcommand omits `NAME` which confuses my users.

Example code:

```python
#!/usr/bin/python3

import click

@click.group()
@click.argument("name")
@click.pass_context
def main(ctx, name):
    ctx.obj = dict(name=name)

@main.command()
@click.pass_obj
def cmd(obj):
    print("Running CMD for %s" % (obj['name']))

if __name__ == "__main__":
    main()
```

Output:
```
$ python3 /tmp/p.py test cmd
Running CMD for test
$ python3 /tmp/p.py --help
Usage: p.py [OPTIONS] NAME COMMAND [ARGS]...

Options:
  --help  Show this message and exit.

Commands:
  cmd
$ python3 /tmp/p.py test cmd --help
Usage: p.py cmd [OPTIONS]

Options:
  --help  Show this message and exit.
$
```

I would expect the latter output to be
```
Usage: p.py NAME cmd [OPTIONS]
```

### Environment

* Python version: 3.any
* Click version: 7.0
