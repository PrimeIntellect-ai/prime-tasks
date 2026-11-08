api endpoints returning lists of items cause error in openapi
### Description

Given there's an endpoint in openapi spec consisting of a list as root.
When the endpoint gets called and returns back the list
The response is not converted to TextContent and therefor throws an error

### Example Code

```Python

```

### Version Information

```Text
Looks like the issue is fixed by [HIDDEN]
```

### Additional Context

_No response_

### Additional contract requirements

- When an OpenAPI-backed tool calls an endpoint whose root response is a list, return the list data as `TextContent` rather than failing, preserving the list data in its text payload.
