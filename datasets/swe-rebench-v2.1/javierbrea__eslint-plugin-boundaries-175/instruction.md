Support custom messages in `no-private` rule
It is desired to support defining custom messages in `no-private` rule, as well as providing more context in the default error message.
Related to #87

### Additional contract requirements

- A configured `message` must interpolate `${dependency.type}`, `${dependency.elementName}`, `${dependency.parent.type}`, `${dependency.parent.elementName}`, `${file.type}`, `${file.elementName}`, `${file.parent.type}`, and `${file.parent.elementName}` with their corresponding values in the reported error.
- When no custom message is configured, a private-dependency error must identify the offending dependency's element by including both its element type and element name; wording and formatting are otherwise unrestricted.
