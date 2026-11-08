Should not raise "Not found" if error response is 401
From client:

```
>>> client.get_bucket(bucket="source")

Traceback (most recent call last):
  File "output-yaml.py", line 43, in <module>
    main()
  File "output-yaml.py", line 38, in main
    result = introspect_server(client)
  File "output-yaml.py", line 16, in introspect_server
    for bucket in buckets
  File "output-yaml.py", line 16, in <dictcomp>
    for bucket in buckets
  File "output-yaml.py", line 22, in introspect_bucket
    print client.get_bucket(bid)
  File "/home/mathieu/Code/Mozilla/kinto.py/kinto_http/__init__.py", line 243, in get_bucket
    raise BucketNotFound(bucket or self._bucket_name, e)
kinto_http.exceptions.BucketNotFound: (BucketNotFound(...), u'source')

```

From server:

```
"GET   /v1/buckets/source" 401 (3 ms) request.summary agent=python-requests/2.9.1 authn_type=None errno=104 lang=None time=2016-10-28T12:58:09 uid=None


```

### Additional contract requirements

- When `get_bucket` receives a 401 error, it must raise a `KintoException` (not a `BucketNotFound`) whose `response` and `request` match those of the original exception and whose message is exactly `Unauthorized. Please authenticate or make sure the bucket can be read anonymously.`
