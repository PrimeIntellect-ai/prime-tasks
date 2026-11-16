Support to add custom error classes based on `HTTPError`
Refactor the `HTTPError` class to support adding custom error classes, for example:

```python
from apiflask import HTTPError

class NotAuthor(HTTPError):
    status_code = 400
    message = 'Only the author can perform this action!'
    extra_data = {
        'error_code': 1234,
        'docs': 'http://example.com'
    }
```

Raise the error in the view:

```python
@app.get('/')
def hello():
    if not author:
        raise NotAuthor
    return 'Hello!'
```
