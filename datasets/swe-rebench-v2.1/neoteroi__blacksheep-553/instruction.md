Verify requirements for schema names for generics
In the following example, BlackSheep generates an OpenAPI Schema containing (_[_ and _]_), when using [Generic models](https://docs.pydantic.dev/latest/concepts/models/#generic-models).

The following is still true:
_$ref values must be RFC3986-compliant percent-encoded URIs_

```python
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from openapidocs.v3 import Info
from pydantic import BaseModel

from blacksheep import Application, get
from blacksheep.server.openapi.v3 import OpenAPIHandler


class DataModel(BaseModel):
    number: int


class Response[DataT](BaseModel):
    data: DataT


app = Application()


docs = OpenAPIHandler(info=Info(title="Example API", version="0.0.1"))
docs.bind_app(app)


@dataclass
class Cat:
    id: UUID

    name: str
    creation_time: datetime


@get("/example")
def generic_example() -> Response[Cat]: ...
```

```yaml
openapi: 3.1.0
info:
    title: Example API
    version: 0.0.1
paths:
    /example:
        get:
            responses:
                '200':
                    description: Success response
                    content:
                        application/json:
                            schema:
                                $ref: '#/components/schemas/Response[Cat]'
            operationId: generic_example
servers: []
components:
    schemas:
        Cat:
            properties:
                id:
                    format: uuid
                    title: Id
                    type: string
                name:
                    title: Name
                    type: string
                creation_time:
                    format: date-time
                    title: Creation Time
                    type: string
            required:
            - id
            - name
            - creation_time
            title: Cat
            type: object
        Response[Cat]:
            properties:
                data:
                    $ref: '#/components/schemas/Cat'
            required:
            - data
            title: Response[Cat]
            type: object
tags: []
```

### Additional contract requirements

- Add a public class `DefaultSerializer` in module `blacksheep.server.openapi.common`.
- `DefaultSerializer` exposes a public method `get_type_name_for_generic(name: str) -> str`. Given a type name that may contain generic syntax in square brackets, it returns a name suitable for use as an OpenAPI component key: square brackets are replaced with `Of`, the closing bracket is removed, and commas together with any following whitespace are replaced with `And`. For example, `get_type_name_for_generic("Example[Foo, Bar]")` returns `"ExampleOfFooAndBar"`.
- Generated schema component names and the schema identifier after `#/components/schemas/` in a `$ref` contain only letters, digits, hyphens, underscores, and periods. `$ref` values use the local `#/components/schemas/` prefix and resolve to their corresponding schema components.
