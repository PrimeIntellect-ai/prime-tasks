zipimport rewritten
The built-in `from zipimport import zipimporter` is rewritten as `from zip import zipimporter` and classified as third party.

### Additional contract requirements

- Imports whose names end in `from` must not be mangled. For example, `from foo import get_foo_from, get_foo` is sorted to `from foo import get_foo, get_foo_from`.
- The built-in `zipimport` module is standard library, not third party. For example, the input `from zipimport import zipimporter\nimport kate\n` is sorted to `from zipimport import zipimporter\n\nimport kate\n`.
