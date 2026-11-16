Openai components/schema support for things like enums
### Enhancement Description

Today tools can be sent with InputSchemas that have references to components/schema i.e.:

    {'$ref': '#/components/schemas/QueryEnum'}

But there is no way for clients to get at the schema definition itself which means the agent will have trouble using the types.



### Use Case

```
import asyncio
from enum import Enum
from typing import Optional

from fastapi import FastAPI
from fastmcp import FastMCP
from fastmcp.server.openapi import RouteMap, RouteType

class QueryEnum(str, Enum):
    foo = "foo"
    bar = "bar"
    baz = "baz"

api = FastAPI()

@api.get("/items/{item_id}")
def read_item(
    item_id: int,
    query: Optional[QueryEnum] = None,   # ← use your Enum here
):
    return {"item_id": item_id, "query": query}

async def main():
    mcp = FastMCP.from_fastapi(
        api,
        route_maps=[
            RouteMap(
                methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
                pattern=r".*",
                route_type=RouteType.TOOL,
            ),
        ],
    )
    await mcp.run_async(transport="sse")

if __name__ == "__main__":
    asyncio.run(main())
```

### Proposed Implementation

```Python
We could either swap out the reference with the actual definition or include the components.schemas as part of the tool.
```

### Additional contract requirements

Add a public function `compress_schema(schema: dict, prune_params: list[str] | None = None, prune_defs: bool = True, prune_additional_properties: bool = True) -> dict` in the module `fastmcp.utilities.json_schema`.

- When `prune_params` is provided, each named top-level property is removed from `properties`, and any matching entry is removed from `required`.
- When `prune_defs` is True (the default), definitions in `$defs` that are not referenced anywhere in the schema are removed; when it is False, all definitions are retained.
- When `prune_additional_properties` is True (the default), a top-level `additionalProperties` entry whose value is `False` is removed; when it is False, it is retained. Entries whose value is `True` or a schema are always retained.
- The function returns a new schema and leaves the input schema unmodified.
