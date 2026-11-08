GitHub API versioning
GitHub introduced API versioning:
https://github.blog/2022-11-28-to-infinity-and-beyond-enabling-the-future-of-githubs-rest-api-with-api-versioning/

To make sure things don’t break, we may need to pin the version with a request header

### Additional contract requirements

Every request to the GitHub API must include the API version header with the value `2022-11-28`. Header names are case-insensitive. A supplied GitHub token must also be sent as a bearer Authorization header; when no token is supplied, no Authorization header is sent.
