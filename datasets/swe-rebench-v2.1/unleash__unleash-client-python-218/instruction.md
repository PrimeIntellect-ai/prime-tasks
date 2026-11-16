Add retries to get_feature_toggles
**Is your feature request related to a problem? Please describe.**
HTTP requests in get_feature_toggles might fail due to intermittent network issues.

Since this is called quite often, it could create plenty of long stack traces, since the entire stack trace is printed: https://github.com/Unleash/unleash-client-python/blob/main/UnleashClient/api/features.py#L67


**Describe the solution you'd like**
Retry the request a couple of times and log only in situations where it does not recover.


I'd be happy to provide a proposal fo this.

### Additional contract requirements

- For HTTP 500 responses, retry up to three times after the initial request, stopping if a retry succeeds; if every attempt returns HTTP 500, make four total requests.

- Retry a transient request or network failure; when a later attempt succeeds, return its response without logging the failure.
- If all attempts fail and the request does not recover, log the failure.
