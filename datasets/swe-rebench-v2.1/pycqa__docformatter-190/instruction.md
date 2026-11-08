List index out of range when formatting docstring with URL
I'm on newly-released docformatter 1.6.3. When I run on a docstring of the following format, I get an `IndexError: list index out of range` at `File ".../lib/python3.11/site-packages/docformatter/syntax.py", line 341, in do_split_description
    if _lines[-1] == "":`

```python
def method():
    """This method doesn't do anything.

    https://example.com/this-is-just-a-long-url/designed-to-trigger/the-wrapping-of-the-description
    """
```
```bash
$ docformatter test.py
Traceback (most recent call last):
  File "/Users/nate/testenv/bin/docformatter", line 8, in <module>
    sys.exit(main())
             ^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/__main__.py", line 71, in main
    return _main(
           ^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/__main__.py", line 61, in _main
    return formator.do_format_files()
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 158, in do_format_files
    result = self._do_format_file(filename)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 191, in _do_format_file
    formatted_source = self._do_format_code(source)
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 236, in _do_format_code
    _code = self._format_code(source)
            ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 301, in _format_code
    token_string = self._do_format_docstring(
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 393, in _do_format_docstring
    return self._do_format_multiline_docstring(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/format.py", line 496, in _do_format_multiline_docstring
    description = _syntax.wrap_description(
                  ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/syntax.py", line 519, in wrap_description
    lines = do_split_description(text, indentation, wrap_length)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/nate/testenv/lib/python3.11/site-packages/docformatter/syntax.py", line 341, in do_split_description
    if _lines[-1] == "":
       ~~~~~~^^^^
IndexError: list index out of range
```

If I add any text between the summary line and the URL, then this goes away:

```python
def method():
    """This docstring does not trigger an error.

    a
    https://example.com/this-is-just-a-long-url/designed-to-trigger/the-wrapping-of-the-description
    """
```
