exception: callable is not supported by signature [ new in 1.14.0 ]
Since my build picked up `sphinx-autodoc-typehints==1.14.0` I get this error when running` make -C docs confluence`:

```
Extension error (sphinx_autodoc_typehints):
Handler <function process_docstring at 0x7f293ebc15f0> for event 'autodoc-process-docstring' threw an exception (exception: callable <0 * DateOffsets> is not supported by signature)
make: *** [confluence] Error 2
```

If I downgrade to 1.13.1 the build runs fine. I ran with `export SPHINXOPTS="-nWT --keep-going -vvv"` and got this (and a much longer stacktrace):

```
Traceback (most recent call last):
  File "venv/lib/python3.7/site-packages/sphinx/util/inspect.py", line 645, in signature
    signature = inspect.signature(subject, follow_wrapped=follow_wrapped)
  File "lib/python3.7/inspect.py", line 3083, in signature
    return Signature.from_callable(obj, follow_wrapped=follow_wrapped)
  File "lib/python3.7/inspect.py", line 2833, in from_callable
    follow_wrapper_chains=follow_wrapped)
  File "lib/python3.7/inspect.py", line 2396, in _signature_from_callable
    raise ValueError('callable {!r} is not supported by signature'.format(obj))
ValueError: callable <0 * DateOffsets> is not supported by signature

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "venv/lib/python3.7/site-packages/sphinx/events.py", line 101, in emit
    results.append(listener.handler(self.app, *args))
  File "venv/lib/python3.7/site-packages/sphinx_autodoc_typehints/__init__.py", line 453, in process_docstring
    signature = sphinx_signature(obj)
  File "venv/lib/python3.7/site-packages/sphinx/util/inspect.py", line 648, in signature
    signature = inspect.signature(subject)
  File "lib/python3.7/inspect.py", line 3083, in signature
    return Signature.from_callable(obj, follow_wrapped=follow_wrapped)
  File "lib/python3.7/inspect.py", line 2833, in from_callable
    follow_wrapper_chains=follow_wrapped)
  File "lib/python3.7/inspect.py", line 2396, in _signature_from_callable
    raise ValueError('callable {!r} is not supported by signature'.format(obj))
ValueError: callable <0 * DateOffsets> is not supported by signature
```

here's a code snippet that generates this error:

```python
from dataclasses import dataclass
from pandas.tseries.offsets import BaseOffset, DateOffset

@dataclass(frozen=True)
class MyClass:
    """Hello."""
    my_field: Union[int, BaseOffset] = DateOffset(0)
    """Hi."""
```

here's my environment:
```
sphinx-autodoc-typehints==1.14.0
sphinxcontrib-applehelp==1.0.2
sphinxcontrib-confluencebuilder==1.6.0
sphinxcontrib-devhelp==1.0.2
sphinxcontrib-htmlhelp==2.0.0
sphinxcontrib-jsmath==1.0.1
sphinxcontrib-qthelp==1.0.3
sphinxcontrib-serializinghtml==1.1.5
```

and here's some potentially relevant bits of of my conf.py:

```python
extensions = [
    "m2r2",
    "sphinx.ext.autodoc",
    "sphinx_autodoc_typehints",
    "sphinx.ext.todo",
    "sphinx.ext.intersphinx",
    "sphinx.ext.coverage",
    "sphinxcontrib.confluencebuilder",
]

# -- External mapping ------------------------------------------------------------
python_version = ".".join(map(str, sys.version_info[0:2]))
intersphinx_mapping = {
    "sphinx": ("https://www.sphinx-doc.org/en/master", None),
    "python": ("https://docs.python.org/" + python_version, None),
    "matplotlib": ("https://matplotlib.org", None),
    "numpy": ("https://numpy.org/doc/stable", None),
    "sklearn": ("https://scikit-learn.org/stable", None),
    "pandas": ("https://pandas.pydata.org/pandas-docs/stable", None),
    "scipy": ("https://docs.scipy.org/doc/scipy/reference", None),
}
```

### Additional contract requirements

During autodoc docstring processing, a callable object whose signature cannot be inspected must not cause documentation generation to abort.
