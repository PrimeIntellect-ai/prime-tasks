handling trailing backslash on prediction endpoints
Currently, on Posit Connect, if you add a trailing backslash-- `connectapi.com/myapi/predict/` rather than `connectapi.com/myapi/predict`-- you get a mysterious error:

```python
ConnectionError: HTTPConnectionPool(host='xxx', port=000): Max retries exceeded with url: myapi/predict (Caused by NameResolutionError("<urllib3.connection.HTTPConnection object at 0x2a109ea90>: Failed to resolve 'xxx' ([Errno 8] nodename nor servname provided, or not known)"))
```

right now, there is no url handling in the `vetiver_endpoint` function, but that might be a good place to ensure links are in the correct format.

FWIW: this error does not occur on a local endpoint or local on Docker

### Additional contract requirements

When `vetiver_endpoint` receives a prediction endpoint URL ending in `/`, it returns that URL without the trailing slash. When the URL does not end in `/`, it returns the URL unchanged.
