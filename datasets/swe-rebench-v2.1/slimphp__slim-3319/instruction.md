HTML Entity Encoding in PlainTextErrorRenderer
## Description
The `PlainTextErrorRenderer` in Slim Framework applies HTML entity encoding to exception messages via the `htmlentities` function. This behavior leads to the encoding of special characters in log messages and other plain text outputs, which might not be desired in all contexts.

## Slim Framework Version
4

## Steps to Reproduce
1. Use the `PlainTextErrorRenderer` to handle exceptions.
2. Trigger an exception with a message that includes characters that are typically encoded by `htmlentities` (like double quotes).
3. Observe the output (in logs, terminal, etc.) and notice that characters are HTML entity encoded (e.g., double quotes are converted to `&quot;`).

## Expected Behavior
In a plain text context, one would expect the error message to be rendered as-is, without HTML entity encoding. The use of `htmlentities` might be more appropriate for HTML-specific renderers.

## Actual Behavior
The error message is HTML entity encoded, leading to representations like `&quot;` in place of double quotes in plain text outputs.

## Possible Solution
[HIDDEN]

## Context
This encoding issue affects logging, CLI outputs, and other scenarios where HTML entity encoding is not desirable in error messages.


https://github.com/slimphp/Slim/blob/fdb6d614700a4e9390c3b08dde96e1f9147ec3fc/Slim/Error/Renderers/PlainTextErrorRenderer.php#L49
