Shell completion fails for option values that start with symbols
Running into the same case as #1929, except specific to option values that may start with symbols such as '+', '~', and '!'. Shell completion treats these values as the start of new options, so doesn't complete them.

Reproduction script with the cli command referenced by setuptools:

```python
class CustomType(click.ParamType):
    name: str = "custom"

    def shell_complete(self, ctx: click.Context, param: click.Parameter, incomplete: str) -> t.List[CompletionItem]:
        values = ["+all", "+one", "+two", "~all", "~one", "~two", "!all", "!one", "!two"]
        return [CompletionItem(v) for v in values if v.startswith(incomplete)]


@click.command()
@click.option("-c", type=CustomType())
def cli(c: t.Optional[str]):
    click.echo(f"Value is {c}")
```

With shell completion enabled:

```sh
$ click-bug -c <TAB><TAB>
+all  +one  +two  ~all  ~one  ~two  !all  !one  !two
$ click-bug -c +<TAB><TAB>
# Nothing happens
```

I was looking at the discussion on #1930, and it makes sense that '+' may be considered the start of an option. I'm wondering if it would be valid for completion to prioritize option values over new option names. As in, [HIDDEN] allows the tab completion in this example to work as expected:

```sh
$ click-bug -c +<TAB><TAB>
+all  +one  +two
```

I can look into putting up a PR to do that if it seems valid.

Environment:

- Python version: 3.6.9
- Click version: 8.0.1
