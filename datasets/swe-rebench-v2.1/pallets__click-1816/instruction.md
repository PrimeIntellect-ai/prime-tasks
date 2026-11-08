Deprecated notice in help text can be hard to see
The current `(DEPRECATED)` deprecation notice added to help text can be hard to see plainly since it can't consider the existing format of the help text.

For example:  I use sphinx style formatting in my help text and if this help text ends with a Note block like below:

```python
def encrypt(ctx, **kwargs):
    """Encrypt archives.

    .. Note::

        Here is a notice.
    """
```

Then a deprecation notice would append to the Note block, making it look like part of the Note and not that the command itself is deprecated.

```shell
Usage: cmd encrypt [OPTIONS]

  Encrypt archives.

  .. Note::

      Here is a notice. (DEPRECATED)
```

I would have expected the deprecation notice to be at the top of my help text making it clear to the user that this command is deprecated.  Or at the least a couple a new lines added to differentiate the notice from any existing help text.

Environment:

- Python version: Python 3.7.9
- Click version: click==7.1.2
