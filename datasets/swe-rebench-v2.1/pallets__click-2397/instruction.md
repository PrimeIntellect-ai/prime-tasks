Issue UserWarning when overriding Parameter name
When a command is given multiple parameters that use the same name, a UserWarning should be fired to highlight the conflict. Currently, the command will quietly allow one parameter to override the names of another.

(This is a slightly different problem than https://github.com/pallets/click/issues/1465. In that issue, True and False values were given the same names within a single parameter.)

**Example of the issue:**

```python
@click.command()
@click.option("-a", "--aardvark", is_flag=True)
@click.option("-a", "--avocado", is_flag=True)
def cli(aardvark: bool = False, avocado: bool = False):
    if aardvark:
        print("Animal")
    if avocado:
        print("Fruit")
```

In this scenario, the short-name, `-a`, appears ambiguous. A warning would help the user realize the conflict they've introduced.

I'll also provide a pull request for consideration.
