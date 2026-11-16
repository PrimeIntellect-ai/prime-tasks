Add `afterResponse` hook
https://github.com/sindresorhus/ky/issues/29
Add `beforeRetry` hook
Feature request to add a hook `beforeRetry` that is called before each retry attempt (possibly with the retry count).

My use-case is logging specific, however it could work identically to `beforeRequest` to allow modifiying the request options for each retry.

### Additional contract requirements

- Each `afterResponse` hook callback must receive the completed response object, including its response body.
