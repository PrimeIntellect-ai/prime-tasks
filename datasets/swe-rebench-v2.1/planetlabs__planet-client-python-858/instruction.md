Add a method to get a client from a Session instance
As in AWS boto3: https://boto3.amazonaws.com/v1/documentation/api/latest/guide/session.html#custom-session. For planet, this would look like

```python
session = planet.Session(...)
client = session.client("data")
```

Currently, we need to do the following.

```
session = planet.Session(...)
client = DataClient(session)
```

There's nothing wrong with this kind of dependency injection, and we're going to keep this usage. But what I'm proposing is more handy and is easy to remember.
