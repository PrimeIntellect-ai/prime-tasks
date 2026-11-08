Raise exception upon name collision when registering components
When registering e.g. two schemas with the same name, the latter silently overwrites the former.

I think we should raise an Exception to inform the user.

Theoretically, it could break code where for some reason the user relied on this (like register a first version, then conditionally register a second version), but this shouldn't be a blocker.

### Additional contract requirements

- When a schema, parameter, or response is registered with a name already registered for that component type, the exception message must be exactly `Another schema with name "{name}" is already registered.`, `Another parameter with name "{name}" is already registered.`, or `Another response with name "{name}" is already registered.`, respectively.
