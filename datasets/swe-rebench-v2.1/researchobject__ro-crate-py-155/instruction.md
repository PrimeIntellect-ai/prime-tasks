Export entities/models in `rocrate.model.__init__`
Hi,

Would it be possible to simplify the imports of ro-crate-py, import/exporting entities like `Person`, `ContextEntity`, `Metadata`, etc, from the `__init__.py` file?

So that instead of having to write

```
from rocrate.model.person import Person
from rocrate.model.contextentity import ContextEntity
from rocrate.model.metadata import Metadata
```

one can do just

```
from rocrate.model import Person, ContextEntity, Metadata
```

Cheers,
Bruno

### Additional contract requirements

- Direct imports from `rocrate.model` must be available for `Person`, `ContextEntity`, `Metadata`, `DataEntity`, `File`, `Dataset`, `ComputationalWorkflow`, `Preview`, `TestService`, `TestInstance`, `TestDefinition`, `TestSuite`, and `SoftwareApplication`.
