Change from 1.5.5 to 1.6.2 results in authentication failure.
We have some code that successfully talks to a Google API using v1.5.5 but breaks under v1.6.2 with the following error:

   "Request is missing required authentication credential. Expected OAuth 2 access token, login cookie or other valid authentication credential"

Our build statement looks like:

     return build(
         'monitoring',
         'v3',
         discoveryServiceUrl=discovery_url,
         developerKey=self.api_key,
         credentials=credentials)

I'm wondering if the following commit may be culprit here:

    https://github.com/google/google-api-python-client/commit/068eb35c9a70e31a42f04d5cb69c36d59e4a2a69

Because we supply both "credentials" and "developerKey" and expect the bearer token / other context from the credentials to be propagated regardless of the presence of "developerKey" (it was my understanding that "developerKey" simply adds a "key=<api-key>" to the discovery URL and to the API requests, but the headers implied by the credentials should still be provided in this case).

Can you fix this? Thanks!

### Additional contract requirements

The fix adopted for this report is to reject the ambiguous combination rather than
silently selecting one authentication mechanism. Concretely:

- `build(...)` must raise `ValueError` when both `credentials` and `developerKey`
  are supplied.
- `build_from_document(...)` must raise `ValueError` when both `credentials` and
  `developerKey` are supplied.

Supplying only `credentials`, only `developerKey`, or neither must continue to
behave as before.
