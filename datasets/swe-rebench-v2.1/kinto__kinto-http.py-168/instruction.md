409 responses are not retried
When the server has a race condition / unicity error, it returns a 409 response.

Currently, kinto-http only retries when server response status code is >= 500.

It should also retry for 409 — not the other 4XX as suggested by @glasserc
