v1.12.7 shows "Content block expected for the "note" directive; none found" with multiple lines of notes
Hello maintainers.

I have a function which has multiple lines of notes, like this:

```py
def func(param1: str) -> None:
    """Do something.

    Args:
        param1: A parameter.

    Note:
        Some notes.
        Some more notes.
    """
    print("Do something")

```

Using v1.12.7, running `sphinx-build` throws an error and a warning like this:

```
ERROR: Content block expected for the "note" directive; none found.
WARNING: Explicit markup ends without a blank line; unexpected unindent.
```

Debugging with `-vv` option, logs show how the method is converted. Seems `:rtype:` is inserted in a wrong place.

```
.. py:function:: func(param1)
   :module: pykit.grpc

   Do something.

   :type param1: :py:class:`str`
   :param param1: A parameter.

   .. note::
   :rtype: :py:obj:`None`

      Some notes.
      Some more notes.
```

This code works fine with v1.12.1, but fails with v1.12.7.
A function with one line of notes works fine with both versions.
Is this an expected or unexpected behavior?
