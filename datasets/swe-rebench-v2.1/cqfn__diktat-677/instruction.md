Allow more prefixes for boolean methods
Like `equals*`, `equivalent*`, or just make it configurable

### Additional contract requirements

- The FUNCTION_BOOLEAN_PREFIX check accepts a boolean-returning function whose name starts with a prefix listed in the rule's `allowedPrefixes` configuration entry. The entry is a comma-separated list of prefixes; whitespace around each prefix is ignored.
- With `allowedPrefixes` set to `equals, equivalent`, a boolean-returning function named `equalsSome` or `equivalentToAnother` produces no FUNCTION_BOOLEAN_PREFIX warning.
