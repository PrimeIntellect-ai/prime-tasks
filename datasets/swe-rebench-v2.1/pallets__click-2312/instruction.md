[HIDDEN]
[HIDDEN]

```python
import click


class ArgumentWithHelp(click.Argument):
    def __init__(self, *args, help=None, **attrs):
        super().__init__(*args, **attrs)
        self.help = help


def argument_with_help(*args, cls=ArgumentWithHelp, **kwargs):
    return click.argument(*args, cls=cls, **kwargs)


my_shared_argument = argument_with_help("pippo", help="very useful help")


@click.command()
@my_shared_argument
def foo(pippo):
    print(pippo)


@click.command()
@my_shared_argument
def bar(pippo):
    print(pippo)
```

Running this file as it is:
```python
Traceback (most recent call last):
  File "C:/Users/sboby/AppData/Roaming/JetBrains/PyCharmCE2022.1/scratches/scratch_4.py", line 27, in <module>
    def bar(pippo):
  File "H:\Repo\unbox\UnboxTranslate\venv\lib\site-packages\click\decorators.py", line 287, in decorator
    _param_memo(f, ArgumentClass(param_decls, **attrs))
  File "H:\Repo\unbox\UnboxTranslate\venv\lib\site-packages\click\core.py", line 2950, in __init__
    super().__init__(param_decls, required=required, **attrs)
TypeError: __init__() got an unexpected keyword argument 'help'

Process finished with exit code 1
```

<strike>The `@option`  decorator is affected by the same problem but it won't crash in a similar situation because `click.Option.__init__` ignore extra arguments: it will just silently use `click.Option` as class.</strike>

The `@option` decorator is actually not affected because `attrs` is copied. This copy is nonetheless unnecessary, since [HIDDEN] would be a more straightforward solution.

Environment:

- Python version: irrelevant
- Click version: 8.1.3 (but all versions are affected)

### Additional contract requirements

- A reusable decorator returned by `click.argument` must register its configured custom argument class every time it is applied, including when applied to multiple commands.
