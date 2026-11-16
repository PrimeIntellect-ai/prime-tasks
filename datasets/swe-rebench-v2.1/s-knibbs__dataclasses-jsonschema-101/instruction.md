Any type should generate an empty field schema
The following definition:

```py
@dataclass
class Parameter(JsonSchemaMixin):

    id: str
    type: ParameterTypeEnum
    value: Any
```

leads to schema like this:

```py
{'type': 'object', 'required': ['id', 'type', 'value'], 'properties': {'id': {'type': 'string'}, 'type': {'type': 'string', 'enum': ['string', 'double']}, 'value': {'type': 'object'}}}
```

But I would rather see:

```py
{'type': 'object', 'required': ['id', 'type', 'value'], 'properties': {'id': {'type': 'string'}, 'type': {'type': 'string', 'enum': ['string', 'double']}, 'value': {}}}
```

...where ```type``` for ```value``` is ommited, which means that ```value``` could be data of any type (string or number in this case). Is there a way how to achieve it? Many thanks.
