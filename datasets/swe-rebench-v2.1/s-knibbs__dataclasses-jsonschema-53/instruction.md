Support `readOnly` and `writeOnly` OpenAPI 3 keywords
OpenAPI 3 supports some [additional keywords](https://swagger.io/docs/specification/data-models/keywords/#extra) for property schemas such as `readOnly` . These could be specified in the field metadata:

```python
@dataclass
class Employee(JsonSchemaMixin):
    id: int = field(metadata=dict(read_only=True), default=-1)
    name: str
    department: str
```
