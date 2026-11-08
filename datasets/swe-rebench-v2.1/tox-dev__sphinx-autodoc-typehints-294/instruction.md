Invalid spacing between `:rtype:` and following directives
In the 1.21.0 release, the position of the emitted `:rtype:` field seems to have changed so that it is now earlier in the docstring, rather than reliably being at the end.  This is fine, except when the place the injector chooses to place it is immediately before a `.. <whatever>::` directive. There doesn't seem to reliable be a blank line inserted after it, and if not, Sphinx complains that the field list ends unexpectedly.

For example, given this Python file `tmp/__init__.py`:
```python
def my_function() -> None:
    """
    .. rubric:: Notes

    Hello, world.
    """
```
and this Sphinx `conf.py`:
```python
project = 'tmp'
extensions = [
    "sphinx.ext.autodoc",
    "sphinx_autodoc_typehints",
]
```
running Sphinx's `make html` gives:
```text
Running Sphinx v6.1.3
loading pickled environment... done
building [mo]: targets for 0 po files that are out of date
writing output...
building [html]: targets for 0 source files that are out of date
updating environment: 0 added, 1 changed, 0 removed
reading sources... [100%] index
/Users/jake/tmp/autodoc-typehints/pkg/tmp/__init__.py:docstring of tmp.my_function:1: WARNING: Field list ends without a blank line; unexpected unindent.
looking for now-outdated files... none found
pickling environment... done
checking consistency... done
preparing documents... done
writing output... [100%] index
generating indices... genindex py-modindex done
writing additional pages... search done
copying static files... done
copying extra files... done
dumping search index in English (code: en)... done
dumping object inventory... done
build succeeded, 1 warning.
```

The docstring enters `_inject_types_to_docstring` as
```text
.. rubric:: Notes

Hello, world.

```
and is modified to
```text
:rtype: :py:obj:`None`
.. rubric:: Notes

Hello, world.

```

This also happens if there's any regular text before the `.. rubric:: notes` as well (which is a bit more of a realistic scenario).
