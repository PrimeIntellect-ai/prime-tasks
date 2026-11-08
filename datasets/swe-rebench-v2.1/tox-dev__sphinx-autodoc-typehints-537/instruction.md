Render issue with versionchanged directive
Test case:
```python
def test() -> None:
    """
    Test

    .. versionchanged:: 1.1.0
    """
    pass
```
is rendered as:
```python
"""
Test :rtype: None

Changed in version 1.1.0.
"""
```
tested with commit 071901d3b

similar to https://github.com/tox-dev/sphinx-autodoc-typehints/issues/467

### Additional contract requirements

- The `:rtype:` directive must be placed after block directives in the docstring body (for example `versionchanged` and `seealso`), not before them. When a docstring contains such a directive, the rendered directive content (e.g. `Changed in version 1.1.0.` or `See also: ...`) must appear before the `Return type:` section, and `:rtype:` must not be joined onto the preceding text line.
