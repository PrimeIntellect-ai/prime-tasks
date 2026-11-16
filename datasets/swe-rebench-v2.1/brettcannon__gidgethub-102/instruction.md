Handle case when GitHub doesn't return JSON error
So I've done _something_ wrong and got HTTP 422 (it wasn't obvious from logs, only from checking sansio code...):
```python-traceback
  File "/app/.heroku/python/lib/python3.7/site-packages/gidgethub/abc.py", line 82, in _make_request
    data, self.rate_limit, more = sansio.decipher_response(*response)
  File "/app/.heroku/python/lib/python3.7/site-packages/gidgethub/sansio.py", line 309, in decipher_response
    errors = data.get("errors", None)
AttributeError: 'str' object has no attribute 'get'
```

It would be nice if gidgethub was emitting more logs so that it'd be easier to debug such things.

And, of course, maybe it should process this more gracefully...

P.S. I still don't know what the error response is. Will have to patch some things to get to it.

### Additional contract requirements

- For a 422 response whose body is not JSON, response processing must raise an HTTP error rather than fail while handling the body as JSON.
- The raw response body must remain available to callers for diagnosis, either in the rendered error message or through a public string-valued attribute; no particular exception subclass or attribute name is required.
- Additional diagnostic logging is not required; making the raw response body available through the error is sufficient to address the debugging request.
