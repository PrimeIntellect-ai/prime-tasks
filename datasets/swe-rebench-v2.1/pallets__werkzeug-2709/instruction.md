calls to `iri_to_uri` fails when the argument is a bytestring
Calls to `iri_to_uri` fails when the argument is a bytestring. Here's an example:

```console
>>> from werkzeug import urls
>>> urls.iri_to_uri(b'/foo')
<stdin>:1: DeprecationWarning: Passing bytes is deprecated and will not be supported in Werkzeug 3.0.
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/midchildan/Documents/playground/werkzeug/lib/python3.10/site-packages/werkzeug/urls.py", line 983, in iri_to_uri
    iri = iri.decode(charset)
TypeError: decode() argument 'encoding' must be str, not None
```

This is what should've happened instead:

```console
>>> from werkzeug import urls
>>> urls.iri_to_uri(b'/foo')
>>> '/foo'
```

Environment:

- Python version: 3.10.11
- Werkzeug version: 2.3.4
