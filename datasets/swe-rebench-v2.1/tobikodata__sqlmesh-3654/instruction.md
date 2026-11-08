@SCHEMA_NAME.model_name is not rendered in python models
I've a variable called `schema_name` defined in sqlmesh config yaml, I use this in all my sql models and its working fine.

I recently created a python model using the below config, but the name is actually not rendered and gives me the error

```
@model(
    name="@schema_name.model_name",
    description="model",
    kind={"name": ModelKindName.FULL},
    columns={..},
)
def execute(...
```

> Error:
> KeyError: '"iceberg".@schema_name."model_name"'

did I use them correctly in the model decorator args? or do we not yet have an option to use sqlmesh vars in the name parameter?

### Additional contract requirements

- User-defined variables supplied to a Python model are applied when rendering the model's `name` and its `depends_on` list.
- When a Python model declares `depends_on`, the arguments passed to `context.resolve_table` do not need to be resolvable at parse time; the model's dependency list is the declared `depends_on`.
- When a Python model does not declare `depends_on`, an argument passed to `context.resolve_table` that cannot be resolved at parse time raises a `ConfigError`.
- Only variables that the model actually references are kept; other supplied variables are ignored.
