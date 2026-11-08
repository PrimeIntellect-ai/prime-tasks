HEAD fails on compressed response
```
$ xh head httpbin.org/gzip
[...]
xh: error: error decoding gzip response body: failed to fill whole buffer
```
This didn't happen before #241, so reqwest deals with it correctly. I don't know how.
