Customization of base_paths for relative imports
Currently, the `base_paths` for relative grammar imports only base on following, if I understood correctly:

1. the directory where the grammar file(-like object) is (fetching from the grammar file path)
2. the directory where the main script is (fetching from `sys.modules['__main__'].__file__`

However, this limits the architecture of projects that are using `lark`.

Imagine we have the following architecture:

```
|- package/
    |- submodule1/
        |- parser.py            # with a string grammar wanting to import some
                                # shared rules/terminals from the shared grammar
    |- submodule2/              # maybe I have another submodule that wants to
                                # import some rules/terminals from the shared grammar
    |- shared/
        |- grammar/
            |- shared.lark      # some shared rules/terminals
                                # say we have a terminal `INT` defined for the example below
```

Well, we could probably use 2) listed above to do the relative imports?

```lark
// not sure if this works
%import .shared.grammar.shared.INT
```

However, this doesn't run if the package is not running independently. For example, using `pytest`, since `sys.modules['__main__'].__file__` will become the path to `pytest`.

**Ideas/Proposals:**

1. Reading paths from an env variable, say `LARK_GRAMMAR_PATH` (just like `PYTHON_PATH`)
2. Opening the `source` argument from `Lark` construct to allow overridden from outside.
3. Allowing pre-loaded grammar by `load_grammar.load_grammar`, since this function already allows specification of `grammar_name`, where the `base_paths` can fetch from

    With the above architecture, say in `parser.py`, we can do:
    ```python
    from pathlib import Path
    SHARED_GRAMMER= str(Path(__file__).parent.parent.joinpath('shared', 'grammar', 'shared.lark').resolve())
    grammar = load_grammar.load_grammar(
        r"""
        start: INT

        %import .shared.INT
        """,
        SHARED_GRAMMER
    )
    parser = Lark(grammar, ...)
    ```

    Then in `Lark` construct, we need to tell if the grammar is pre-loaded:
    ```python
    from load_grammer import Grammar

    class Lark:
        def __init__(self, grammar, ...):
             if isinstance(grammar, Grammar):
                 self.grammar = grammar
                 self.source = '<pre-loaded>'
                 # may have to deal with caching separately in such case
             else:
                 # regular grammar loading
    ```

### Additional contract requirements

- Add a public class `FromPackageLoader` in module `lark.load_grammar`, constructed as `FromPackageLoader(pkg_name, search_paths=("",))`. `pkg_name` is the name of the package that contains the grammar resources. `search_paths` is a tuple of directories inside that package that are searched for absolute imports; it defaults to `("",)`, i.e. the package root.
- A `FromPackageLoader` instance is callable as `loader(base_path, grammar_path)` and returns a two-tuple `(resource, text)`. `resource` is a `PackageResource` describing the located grammar file, and `text` is the decoded grammar source. `base_path` is `None` for absolute imports, or the location of the importing grammar for relative imports.
- Add a public class `PackageResource` in module `lark.load_grammar` with attributes `pkg_name` (the package name) and `path` (the package-relative path of the located grammar file).
- `Lark(...)` accepts an `import_paths` keyword argument: a list of loader callables of the form `(base_path, grammar_path) -> (name, source)`, such as `FromPackageLoader` instances. These loaders are consulted, in order, when resolving `%import` statements.
