Mounted Server Lifespans
### Description

It looks like the generics on FastMCP require the mounted servers and the root server to share the same lifespan context type object?

It also looks like mounted server lifespans are never invoked
```
from contextlib import asynccontextmanager
from logging import getLogger
from fastmcp.server import FastMCP

@asynccontextmanager
async def mounted_lifespan(app):
    """Lifespan context manager for the MCP server."""
    raise "Running mounted lifespan."


mcp = FastMCP(name="Parent MCP Server")

mcp.mount(
    "/mounted",
    FastMCP(name="Mounted MCP Server", lifespan=mounted_lifespan),
)

if __name__ == "__main__":
    mcp.run(transport="sse")
```

and when using the tool only the context from a lifespan on the root server is available

### Example Code

```Python

```

### Version Information

```Text
2.2.6
```

### Additional Context

_No response_

### Additional contract requirements

When a mounted server with a custom lifespan is served through its root server, that lifespan is entered. Tools on the mounted server can access the context yielded by that mounted server's lifespan.
