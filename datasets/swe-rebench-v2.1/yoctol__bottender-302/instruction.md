ConsoleBot fallbackMethods support sendText second argument?
In Messenger, we put quick replies and other options like tag in second argument. But those will be ignored when using ConsoleBot with `fallbackMethods`.

### Additional contract requirements

- `ConsoleContext` accepts a `fallbackMethods` option.
- When a `ConsoleContext` is created with `fallbackMethods: true` and `sendText(text, ...args)` is called with one or more extra arguments, the message sent is `text`, followed by a newline, the literal `with other args:`, a newline, and the extra arguments serialized as pretty-printed JSON with two-space indentation.
- When `fallbackMethods` is not enabled, `sendText` forwards only the text and ignores any extra arguments.
