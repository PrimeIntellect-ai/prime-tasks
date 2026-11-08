Make clients case sensitive
Following up from https://github.com/boto/boto3/issues/171, this should *not* be allowed:


```
>>> import botocore.session
>>> session = botocore.session.get_session()
>>> session.create_client('S3')
<botocore.client.S3 object at 0x10368e2b0>
```

Our reference docs has all the services in lower case, and all our examples use lower case, so we should enforce that this is what you specify.  It's also what you get back from `session.get_available_services()`.

### Additional contract requirements

- `session.create_client(service_name, ...)` must reject a service name whose
  case does not exactly match a canonical lower-case service name. In
  particular, `session.create_client('S3')` must not succeed; it must raise
  `botocore.exceptions.ValidationError`.
- A canonical lower-case service name (for example `session.create_client('s3')`)
  must still succeed and return a client instance.
