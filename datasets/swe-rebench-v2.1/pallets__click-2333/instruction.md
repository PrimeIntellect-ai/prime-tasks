Invalid info_name with shiv and pex
## Summary

When Click is used inside zipapps produced by Shiv or PEX, it displays an invalid "Usage" string. Instead of "Usage: program" it says "Usage: python -m program".

I did some digging and found that this is due to *info_name* being guessed incorrectly in the code introduced by #1609. There is a [test for `__package__` being set to `None`](https://github.com/MLH-Fellowship/click/blob/faaec8294eb819e9f8e6f568ae81b711a861ebbe/src/click/utils.py#L470); however, in the case when the script is run inside Shiv or PEX, `__package__` is instead set to the empty string (""). This is allowed by PEP 366:

> Note that setting __package__ to the empty string explicitly is permitted, and has the effect of disabling all relative imports from that module (since the import machinery will consider it to be a top level module in that case).

## Reproducing

Follow the basic [Shiv hello world example](https://shiv.readthedocs.io/en/latest/#hello-world), but add Click:

_hello.py_:
```python
import click

@click.command()
def main():
    print("Hello world")

if __name__ == "__main__":
    main()
```

_setup.py_:
```python
from setuptools import setup

setup(
    name="hello-world",
    version="0.0.1",
    description="Greet the world.",
    py_modules=["hello"],
    entry_points={
        "console_scripts": ["hello=hello:main"],
    },
    install_requires=['Click==8.1.3'],
)
```

Build the executable zipapps and run them:
```text
$ shiv . -c hello -o hello1.pyz
$ pex . -c hello -o hello2.pyz

$ ./hello1.pyz --help
Usage: python -m hello1 [OPTIONS]

$ ./hello2.pyz foo
Usage: python -m hello2 [OPTIONS]
Try 'python -m hello2 --help' for help.
```

## Expected behavior

Click should not print the Usage string as "python -m hello"; it should just be "hello".

## Environment:

- Python version: 3.10.5
- Click version: 8.1.3
- Shiv version: 1.0.1
- Pex version: 2.1.102
