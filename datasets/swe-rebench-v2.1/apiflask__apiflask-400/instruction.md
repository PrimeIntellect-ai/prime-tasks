Cannot return non-dictlike object from handler if BASE_RESPONSE_SCHEMA is set
If BASE_RESPONSE_SCHEMA is set and a non-dict like object is returned from a route, an exception `TypeError: argument of type '<type of object>' is not iterable` is thrown from [scaffold.py](https://github.com/apiflask/apiflask/blob/71c821ae59494b455d95f6df2e0f85c086652c23/src/apiflask/scaffold.py#L469) when checking `if data_key not in obj` (the `in` keyword doesn't work on all objects).

Environment:

- Python version:
- Flask version:
- APIFlask version:
