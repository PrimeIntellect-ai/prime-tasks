Add documentation to accessor methods.
The accessor functions with the pattern `as_triplegs.xyz` do not have a complete documentation, but rather refer to the wrapped functions in a different modules. This is inconvenient for working in an editor, as one cannot look up the functionality of the various parameters in the docstring. Instead one has to look up the referenced docstring seperatly.

Two ways to change that would be:
1. Just copy the docstring over at every change.
2. Use a decorator to copy the docstring directly.

The first way is rather error-prone as one has to remember to change both docstrings at any change. Here it would be good to write a test that checks the equality of the `__doc__` attribute of the functions. The second way can be unclear in the documentation as it replaces silently the existing docstring. Also other problem arises in terms of circular imports etc. .

### Additional contract requirements

- Add a public function `copy_docstring(wrapped)` in module `trackintel.model.util`. Applying it as a decorator to a function copies the docstring of `wrapped` onto the decorated function.


- The docstring of `TriplegsAccessor.to_csv` must include the docstring of `write_triplegs_csv`, and the docstring of `TriplegsAccessor.to_postgis` must include the docstring of `write_triplegs_postgis`.
