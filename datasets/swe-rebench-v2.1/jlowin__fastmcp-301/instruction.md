Compatibility with official mcp and running in-memory
### Enhancement Description

I do not need to run my MCP as a server as I'm doing everything from Python. So I've been trying to experiment with this approach:

```py
from agents.mcp import MCPServer, MCPServerStdio
from mcp.types import Tool as MCPTool, CallToolResult


class MCPFakeServer(MCPServer):
    fastmcp: FastMCP

    def __init__(self, fastmcp: FastMCP):
        self.fastmcp = fastmcp

    async def connect(self):
        return

    def name(self) -> str:
        return self.fastmcp.name

    async def cleanup(self):
        return

    async def list_tools(self) -> list[MCPTool]:
        async with Client(self.fastmcp) as client:
            return await client.list_tools()

    async def call_tool(self, tool_name: str, arguments: dict[str, Any] | None):
        async with Client(self.fastmcp) as client:
            return await client.call_tool(tool_name, arguments)
```

I have two problems with the following approach:

1. the compatibility between the types of mcp and fastmcp. For example, I can't return an exact type from `call_tool` because the types don't match
2. the use of globals. This is annoying as I want multiple agents to call this fake MCPServer with different fixed variables. I can't have these variables be part of the arguments as agents should not be able to control them, but having them as globals would not allow me to have different ones


### Use Case

_No response_

### Proposed Implementation

```Python

```

### Additional contract requirements

The client must provide public raw MCP operations named `list_tools_mcp`, `call_tool_mcp`, `list_resources_mcp`, `read_resource_mcp`, `list_prompts_mcp`, `get_prompt_mcp`, and `list_resource_templates_mcp`, corresponding to the client operations with the same names without the `_mcp` suffix. Each raw operation returns the complete official MCP protocol result object, including its operation-specific result fields, rather than a simplified list or content value. These operations must work when the client communicates with an in-memory FastMCP server. In particular, `call_tool_mcp` returns a tool-call result with its error flag and content instead of raising the client-facing tool error for an unsuccessful tool call.
