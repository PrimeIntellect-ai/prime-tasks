etag value has extra backslashes when uploading object
When uploading an object against a `fake-gcs-server`, I'm noticing that the `etag` value has escaped backslashes before and after the actual md5 hash. Looks to be due to poor escaping. A GCS client library that I'm using fails to parse the `etag` attribute because of this. I wasn't able to repro when uploading against GCS itself.

Raw json output when uploading against `fake-gcs-server`:
```
"... , \"etag\": \"\\\"1B2M2Y8AsgTpgAmY7PhCfg==\\\"\", ..."
```

Raw json output when uploading against GCS itself:
```
"... , \"etag\": \"TKb9iteyqIEDEEE=\", ..."
```
