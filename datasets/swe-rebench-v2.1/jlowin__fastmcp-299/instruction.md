Add support for tool annotations
### Enhancement Description

The MCP spec includes [a section for tool annotations](https://modelcontextprotocol.io/docs/concepts/tools#tool-annotations), allowing you to, among other things, provide human readable names to the consuming tools. Presently I don't see a way to pipe these annotations through the `@tool` decorator.

### Use Case

For my part I'd like to provide more human names for tools than the `name` parameter allows, but the uses cases are mostly provided in the spec itself.

### Proposed Implementation

Add an `Annotations` `@dataclass` for use in the tool decorator:

```python
@dataclass
class Annotations:
    title: str = None
    read_only_hint: bool = false
    destructive_hint: bool = true
    idempotent_hint: bool = false
    open_world_hint: bool = true
```

And expose the ability to apply this class from the top level decorator:

```python
@mcp.tool(annotations = Annotations(title="Start a MyCompany™ FooBar job")
def do_my_company_foo_bar:
    pass
```

### Additional contract requirements

Callers must be able to provide a human-readable title and the read-only, destructive, idempotent, and open-world hints through `@mcp.tool(...)`, and MCP consumers must receive those values. Callers may supply the MCP SDK's caller-usable `ToolAnnotations` type as the proposed `Annotations` value, using its title and protocol hint fields; a separate FastMCP `Annotations` class is not required. Supporting this SDK type is required, and its name and field names are discoverable from the SDK. Annotation metadata must be observable through the client-facing tool listing. This request does not require annotation support through the separate `add_tool` method.
