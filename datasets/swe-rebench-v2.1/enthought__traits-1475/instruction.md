DeprecationWarning with latest Sphinx: no_docstring is deprecated.
When running the Traits test suite with the latest Sphinx (3.5.1) from PyPI, I see the following `DeprecationWarning`:

```
/Users/mdickinson/Enthought/ETS/traits/traits/util/trait_documenter.py:80: RemovedInSphinx50Warning: The 'no_docstring' argument to TraitDocumenter.add_content() is deprecated.
```

### Additional contract requirements

- Documenting a trait attribute through the Traits Sphinx documenter with Sphinx 3.5.1 or later should not emit a Sphinx deprecation warning about the `no_docstring` argument.
