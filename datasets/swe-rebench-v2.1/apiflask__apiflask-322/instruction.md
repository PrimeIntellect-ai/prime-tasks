Allow returning list as JSON response
Like how dict return value was handled:

```py
@app.get('/')
def many():
    return ['foo', 'bar', 'baz']  # -> become JSON response
```

### Additional contract requirements

A view may also return a standard Flask response tuple whose body is a list. The list must be returned as a JSON response, and any status code and headers supplied by the tuple must be preserved. A JSON response is identified by its `application/json` media type; additional media-type parameters do not change that requirement.
