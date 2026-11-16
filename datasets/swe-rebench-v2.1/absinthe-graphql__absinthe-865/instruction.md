Document changes to import_types in 1.5
### Environment

* Elixir version (elixir -v): 1.9.2
* Absinthe version (mix deps | grep absinthe): 1.5.0-rc.2
* Client Framework and version (Relay, Apollo, etc): N/A

Need some documentation around the fact that `import_types` wont work for "batched" imports, the same way it did in 1.4

Previously, this was supported:
```
import_types(__MODULE__.Types.{Category, OtherType, etc... })
```

But in 1.5 we get an error like this:

```
== Compilation error in file lib/my_app_api/schema/schema.ex ==
** (ArgumentError) module Elixir.MyApp.API.Schema.Types.Category is not available
    lib/absinthe/schema/notation.ex:1555: anonymous fn/5 in Absinthe.Schema.Notation.do_import_types/3
    (elixir) lib/enum.ex:1948: Enum."-reduce/3-lists^foldl/2-0-"/3
    lib/absinthe/schema/notation.ex:1549: Absinthe.Schema.Notation.do_import_types/3
    expanding macro: Absinthe.Schema.Notation.import_types/1
    lib/instinct_api/schema/schema.ex:8: Instinct.API.Schema (module)
    (elixir) lib/kernel/parallel_compiler.ex:229: anonymous fn/4 in Kernel.ParallelCompiler.spawn_workers/7
```

This error goes away by changing to syntax like
```elixir
import_types(__MODULE__.Types.Category)
import_types(__MODULE__.Types.OtherType)
import_types(...etc)
```

This seems to be related to how the macro is expanded:
https://github.com/absinthe-graphql/absinthe/blob/v1.5.0-rc.2/lib/absinthe/schema/notation.ex#L1545

Either this needs better documentation (as this could constitute a breaking change for some projects), or should resolve as it did in 1.4

### Additional contract requirements

The batched import syntax relative to `__MODULE__` must be supported again, as it worked in 1.4:

```elixir
import_types __MODULE__.Types.{Category, OtherType}
```

Every module listed inside the braces must be imported so that the types it defines become available in the schema. Concretely, after such an import, `Absinthe.Schema.lookup_type/2` must return the imported type for each listed module. This must hold both for a schema that references sibling modules and for a self-contained schema whose imported modules are defined nested inside the schema module.
