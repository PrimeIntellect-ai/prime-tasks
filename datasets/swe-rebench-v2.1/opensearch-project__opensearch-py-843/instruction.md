[BUG] Async client is missing ssl_assert_hostname implementation
### What is the bug?
The `ssl_assert_hostname` parameter has no effect on the `AsyncOpenSearch` client.

### How can one reproduce the bug?
```python
client = AsyncOpenSearch(hosts='my.opensearch.with.selfsigned.certs', ssl_assert_hostname=False)
await client.search(...)
```
```
opensearchpy.exceptions.ConnectionError: ConnectionError(Cannot connect to host my.opensearch.instance:9200 ssl:True [SSLCertVerificationError: (1, "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: Hostname mismatch, certificate is not valid for 'my.opensearch.instance'. (_ssl.c:1000)")]) caused by: ClientConnectorCertificateError(Cannot connect to host my.opensearch.instance:9200 ssl:True [SSLCertVerificationError: (1, "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: Hostname mismatch, certificate is not valid for 'my.opensearch.instance'. (_ssl.c:1000)")])
```

### What is the expected behavior?
The connection should succeed even if the hostname does not match.

### What is your host/environment?
N/A

### Do you have any screenshots?
N/A

### Do you have any additional context?
The parameter is documented in the function docs:
https://github.com/opensearch-project/opensearch-py/blob/6fa54a719a399cdcd8d970605487b9e14d257383/opensearchpy/_async/http_aiohttp.py#L120

I believe the parameter works with the `urllib3`-based client.

I'm working on a PR to fix this.
