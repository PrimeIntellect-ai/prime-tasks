ValidateError should extend Error
<!--- Provide a general summary of the issue in the Title above -->

## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
- `ValidateError` should extend `Error`

## Current Behavior
- `ValidateError` does not extend `Error`

As a result, tools like [Sentry](https://sentry.io/) do not fully work with `ValidateError`. Sentry makes a [synthetic exception](https://docs.sentry.io/platforms/node/#hints-for-events) and does not include it's full exception info, it only reports:
```
Non-Error exception captured with keys: fields, message, name, status
```

## Possible Solution
- [HIDDEN]

## Steps to Reproduce
1. Generate an express server
2. Make an API request that triggers a validation error, for example: https://github.com/lukeautry/tsoa/blob/313012a1214f0afa95756cf23bbc13f46277499e/tests/integration/express-server.spec.ts#L463-L470
3. `ValidateError` should be thrown, and it should extend `Error`

## Context (Environment)
Version of the library: 2.5.13
Version of NodeJS: 10.16.3
* Confirm you were using yarn not npm - I use npm, not yarn

## Detailed Description
[HIDDEN]

## Breaking change?
- Yes

### Additional contract requirements

- A constructed `ValidateError` must be an instance of `Error` (`instanceof Error` evaluates to `true`).
