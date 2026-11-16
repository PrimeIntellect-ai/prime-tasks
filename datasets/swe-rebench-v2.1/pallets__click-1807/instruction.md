@pass_meta_key decorator
### Idea Proposal:

As a click's plugin developer, we use the `click.Context.meta` dictionary to store any state. So IMHO, click could provide another decorator: `@click.pass_metavar(key="foo")` similar to `@click.pass_obj`.

**Example implementation:**

```python
def pass_metavar(key: str):
    """Similar to :func:`click.pass_obj`,
    this passes the ctx.meta[key] variable instead as the first argument.
    """

[HIDDEN]
```

**Example usage:**

```python
@click.pass_metavar(key="foo")
def bar(var):
    click.echo(var)
```

I think this would be beneficial for click's plugin developers and naturally anyone building a complex CLI app which requires using the `click.Context.meta` to store state.

If you like the idea, I will be glad to raise a PR for it asap.

### Additional contract requirements

The decorator is exposed publicly as `click.decorators.pass_meta_key`; it is importable with `from click.decorators import pass_meta_key`. The `doc_description` parameter is keyword-only: `pass_meta_key(key: str, *, doc_description: str | None = None)`. When supplied, its description is included in the returned decorator's docstring.
