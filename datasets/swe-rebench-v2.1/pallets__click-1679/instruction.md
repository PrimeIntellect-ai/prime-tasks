With argument autocompletion, context is not passed properly
I used the current master revision:

    $ pip3 install git+https://github.com/pallets/click.git@55682f6f5348f5220a557f89c3a796321a52aebf

and an executable file `testclick`:

```python
#!/usr/bin/env python3
import click

def _complete(ctx, args, incomplete):
    return ctx.obj['completions']

@click.group()
@click.pass_context
def entrypoint(ctx):
    pass

@entrypoint.command()
@click.argument('arg', type=click.STRING, autocompletion=_complete)
@click.pass_context
def subcommand(ctx, arg):
    print('arg={}'.format(arg))

entrypoint(obj={'completions': ['abc', 'def', 'ghi', ]})
```

and enabled bash completion with

    eval "$(_TESTCLICK_COMPLETE=source ./testclick)"

Now I am getting an error when trying to use autocompletion:

```
    $ ./testclick subcommand <TAB>Traceback (most recent call last):
  File "./testclick", line 23, in <module>
    entrypoint(obj={'completions': ['abc', 'def', 'ghi', ]})
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/core.py", line 731, in __call__
    return self.main(*args, **kwargs)
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/core.py", line 701, in main
    _bashcomplete(self, prog_name, complete_var)
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/core.py", line 46, in _bashcomplete
    if bashcomplete(cmd, prog_name, complete_var, complete_instr):
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/_bashcomplete.py", line 216, in bashcomplete
    return do_complete(cli, prog_name)
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/_bashcomplete.py", line 205, in do_complete
    for item in get_choices(cli, prog_name, args, incomplete):
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/_bashcomplete.py", line 186, in get_choices
    ctx, all_args, incomplete, param))
  File "/home/user/testclick/venv/lib/python3.6/site-packages/click/_bashcomplete.py", line 124, in get_user_autocompletions
    incomplete=incomplete)
  File "./testclick", line 7, in _complete
    return ctx.obj['completions']
TypeError: 'NoneType' object is not subscriptable
```

Expected behavior was to get a list of completions `abc def ghi`.

I am using Python 3.6.4
