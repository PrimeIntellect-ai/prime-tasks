address deprecations from Werkzeug 2.3
**Describe the bug**
https://github.com/maxcountryman/flask-login/blob/b30758205211c3af4ac6a41601aee17f6aa45f64/src/flask_login/utils.py#L15 is deprecated and will be removed in Werkzeug 2.4

```
/.venv/lib/python3.9/site-packages/flask_login/utils.py:130: DeprecationWarning: 'werkzeug.urls.url_encode' is deprecated and will be removed in Werkzeug 2.4. Use 'urllib.parse.urlencode' instead.
    netloc=netloc, query=url_encode(md, sort=True)
```


**Additional context**
N/A
