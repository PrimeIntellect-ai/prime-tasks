Print on client raises exception
```python
>>> cli = Client(server_url='https://kinto.dev.mozaws.net/v1/', auth=('gabi', 'my_secret'))
>>> cli
Traceback (most recent call last):
  File "/usr/local/lib/python3.6/site-packages/kinto_http/__init__.py", line 53, in get
    return pattern.format(root=self._root, **kwargs)
KeyError: 'collection'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/usr/local/lib/python3.6/site-packages/kinto_http/__init__.py", line 529, in __repr__
    collection=self._collection_name
  File "/usr/local/lib/python3.6/site-packages/kinto_http/__init__.py", line 120, in get_endpoint
    return self.endpoints.get(name, **kwargs)
  File "/usr/local/lib/python3.6/site-packages/kinto_http/__init__.py", line 57, in get
    field=','.join(e.args)))
kinto_http.exceptions.KintoException: (KintoException(...), 'Cannot get collection endpoint, collection is missing')
```

### Additional contract requirements

- When `str(client)` is called with `server_url='https://kinto.notmyidea.org/v1'` and `bucket='homebrewing'` (with no collection), it must return exactly `<KintoClient https://kinto.notmyidea.org/v1/buckets/homebrewing>`. With the same server URL and `bucket=None`, it must return exactly `<KintoClient https://kinto.notmyidea.org/v1/>`.
