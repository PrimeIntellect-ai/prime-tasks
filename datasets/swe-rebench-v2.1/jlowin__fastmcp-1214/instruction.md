FastMCP.from_openapi() takes too much time to create instance
### Description

as described in https://github.com/jlowin/fastmcp/discussions/1191 ,
It takes too long time to create FastMCP instance from openAPI spec.
as the result, production mcp clients, such as VC copilot chat UI, often give up waiting FastMCP ready to serve when transport is stdio.

when replacing deepcopy implementation from builtin copy.deepcopy  into json.dumps+loads, it goes faster and 24% improved. i.e total time decreased to 3/4.

Ideally, we would get it faster, but unfortunately that may be difficult in a realistic time frame.

### Example Code

```Python
# the same as docs/integrations/openapi.mdx

from fastmcp import FastMCP
import httpx

client = httpx.AsyncClient()
# get spec from real production server, such as https://github.com/github/rest-api-description/tree/main/descriptions/*/*.json

spec = httpx.get("https://api.production.server.com/openapi.json").json()
mcp = FastMCP.from_openapi(spec, client=client)
#
# mcp client often gives up waiting FastMCP ready to serve.
#
print("mcp instance created.") # use logger and output message into file other than stdout/stderr, if transport==stdio.
mcp.run(transport='stdio')
```

### Version Information

```Text
FastMCP version:                                       2.10.6
MCP version:                                           1.12.0
Python version:                                        3.12.11

when I tested with python 3.13.5, the above investigation results are almost the same( just noise level differences)
```

### Additional Context

_No response_

### Additional contract requirements

- Constructing a server from an OpenAPI specification (including large specifications with several hundred operations and schema definitions) must complete in under 8 seconds.
