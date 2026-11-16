Improvement for show_default showing in case of a flag the name instead of True/False
First to say: It's not a bug ... it's (in my opinion) a reasonable improvement.

### Expected Behavior

That's how the boolean flag is configured:

```python
@click.option('--cache/--no-cache', default=False, show_default=True,
              help="Enable/Diable the cache.")
```
Using the --help you see following (just the line of interest):

```
--cache / --no-cache        Enable/Diable the cache.  [default: False]
```

but preferable woud be:

```
--cache / --no-cache        Enable/Diable the cache.  [default: no-cache]
```

It's clear to me that this works for --cache/--no-cache like flags only.

### Actual Behavior

The output is as documented by the API the default **value** (*not the name*) which is for a boolean True or False.

### Environment

* Python version: 3.8.1
* Click version: 7.0

### Additional contract requirements

- When multiple true/false option pairs are declared, use the matching option name from the first pair. For `("--cache/--no-cache", "--c/--nc")`, display `[default: cache]` when the default is `True` and `[default: no-cache]` when it is `False`.
