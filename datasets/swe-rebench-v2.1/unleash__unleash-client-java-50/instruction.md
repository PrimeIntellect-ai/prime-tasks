Unable to detect failures in HttpToggleFetcher
The current API of Unleash/HttpToggleFetcher makes it difficult to detect if HttpToggleFetcher is actually able to fetch toggles or if it experiences for example network failures, authentication/authorization failures or simply 404s because because somebody shut down or moved the unleash server.

It would be nice if applications are able to observe such problems through the API.

### Additional contract requirements

A failed toggle fetch must be observable as distinct from both changed and unchanged outcomes. Network or I/O failures and unsuccessful HTTP responses must either produce an unavailable outcome or be surfaced as an exception to the caller.
