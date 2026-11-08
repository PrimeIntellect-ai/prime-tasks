Nullish HTML input should return an empty string.
## The problem to solve

Discussed in #102. Undefined or null input returns 'undefined' and 'null' strings.

## Proposed solution

We return an empty string if the input is nullish

## Alternatives

We could also throw an error in that case, making it the responsibility of the application using sanitize-html to ensure input isn't nullish. I'm not sure there's enough downside to the proposed solution to pass the buck, though.
