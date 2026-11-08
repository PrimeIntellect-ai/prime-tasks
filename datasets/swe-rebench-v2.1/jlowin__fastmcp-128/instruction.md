Support for Customizable Prefix Separator in mount() Method
It would be great to support customizable prefix formats to accommodate integrations that have specific naming.

Currently, when using mcp.mount("weather", weather_mcp), the mounted prefix is automatically joined using "/". However Anthropic Claude API require a specific format for tool names.

For example, Anthropic's Claude API returns the following error when keys contain "/":

```javascript
❌ Claude API error: Error code: 400 - {
  'type': 'error',
  'error': {
    'type': 'invalid_request_error',
    'message': "tools.0.custom.name: String should match pattern '^[a-zA-Z0-9_-]{1,64}$'"
  }
}

```

Probably:
`mcp.mount("weather", weather_mcp, separator="_")`

### Additional contract requirements

`FastMCP.mount` accepts optional string keyword arguments that customize the separator placed between the mount prefix and each imported item's name or URI:

- `tool_separator` controls the separator for imported tool names.
- `resource_separator` controls the separator for imported resource and resource-template URIs.
- `prompt_separator` controls the separator for imported prompt names.

When a separator is not supplied, `tool_separator` and `prompt_separator` default to `_`, and `resource_separator` defaults to `+`.
