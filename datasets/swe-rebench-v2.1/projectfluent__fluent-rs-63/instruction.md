Remove MessageContext.get_message
This is similar to https://github.com/projectfluent/fluent.js/issues/208.

I'd like to change `MessageContext.format()` to accept an identifier of a message and format it directly to a string. It would avoid the intermediate step of having to first `get_message` the message from the context, which is a bit clunky and is an artifact of how the JavaScript bindings retrieve translated attributes.

### Additional contract requirements

- `MessageContext::format` must also accept an attribute path in the form `identifier.attr` and format that attribute directly.
