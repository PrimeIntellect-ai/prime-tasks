Click doesn't close file options during shell completion
Click doesn't close file options during shell completion, which causes a resource warning if a program uses a file option.

For example, I have group like this:

```python
@click.group()
@click.option('--config_file',
              default=CONFIG,
              type=click.File(mode='r'),
              help='help')
@click.pass_context
def cli(ctx, config_file: typing.TextIO):
```

and I get this warning:

```
/Users/grzesiek/Library/Caches/pypoetry/virtualenvs/findata-fetcher-3hK6JJJX-py3.12/lib/python3.12/site-packages/click/shell_completion.py:293: ResourceWarning: unclosed file <_io.TextIOWrapper name='/Users/grzesiek/.config/findata/fetcher.json' mode='r' encoding='UTF-8'>
  completions = self.get_completions(args, incomplete)
```

## Details

I don't come with reproduction steps, but I can give something equally valuable, I can explain how this bug comes to be.

[HIDDEN] Here's a stack-trace of how that happens:

```
  File "/Users/grzesiek/.local/bin/findata-fetcher", line 8, in <module>
    sys.exit(main())
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/fetcher/tool.py", line 576, in main
    cli(obj={})
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/core.py", line 1171, in __call__
    return self.main(*args, **kwargs)
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/core.py", line 1084, in main
    self._main_shell_completion(extra, prog_name, complete_var)
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/core.py", line 1165, in _main_shell_completion
    rv = shell_complete(self, ctx_args, prog_name, complete_var,
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/shell_completion.py", line 49, in shell_complete
    echo(comp.complete())
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/shell_completion.py", line 296, in complete
    completions = self.get_completions(args, incomplete)
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/shell_completion.py", line 273, in get_completions
    ctx = _resolve_context(self.cli, self.ctx_args, self.prog_name, args)
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/shell_completion.py", line 513, in _resolve_context
    ctx = cli.make_context(prog_name, args.copy(), **ctx_args)
  File "/Users/grzesiek/.local/pipx/venvs/findata-fetcher/lib/python3.12/site-packages/click/core.py", line 952, in make_context
    with ctx.scope(cleanup=False):
```

[HIDDEN]

## Environment

- Python version: 3.12
- Click version: 8.1.7

### Additional contract requirements

- Shell completion must clean up files opened while resolving file-valued options, so completion does not leave those resources open and trigger a `ResourceWarning`.
