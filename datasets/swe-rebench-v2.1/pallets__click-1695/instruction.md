Automatic short help should also take linebreak into account
PEP257 defines a summary line for [multi-line docstrings](https://www.python.org/dev/peps/pep-0257/#multi-line-docstrings) just like a [one-line docstring](https://www.python.org/dev/peps/pep-0257/#one-line-docstrings) to be a phrase ending in a period.

Click automatically uses everything up to the first period to be the short help, independent how many lines it spans.

Consider the following:
```
import click

@click.group()
def grp():
    pass

@grp.command()
def cmd1():
    """First sentence. Second sentence."""

@grp.command()
def cmd2():
    """Summary line without a period

    First real sentence. Another sentence.
    """
```
```
$ python3 foo.py  --help
Usage: foo.py [OPTIONS] COMMAND [ARGS]...

Options:
  --help  Show this message and exit.

Commands:
  cmd1  First sentence.
  cmd2  Summary line without a period First real...
```
To me it would feel more natural:
1. to take the first line as short help, independent of punctuation OR
1. to look for an ending of a phrase or linebreak, whichever comes first.

Both would allow for summary lines without the requirement to end in a period. While this would violate PEP257, I would consider it a gray area, as that summary line is used as short help in a list of commands and I have a use case where a company style guide requires such lists **not** to end in periods.

I'd be happy to provide a pull request for either solution, if it would be accepted.
