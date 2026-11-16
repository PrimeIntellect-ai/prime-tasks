ConnectionClosed subclass for normal closure
I was thinking it would be a nice touch to add (and use) a `ConnectionClosed` subclass that corresponds to a normal closure (i.e. status code 1000).

This would make it easier for users to handle expected (normal) closures differently and more elegantly, namely without having to inspect the code attribute. For example, here is one place in the websockets code base that such a pattern could be used:

    try:
        while True:
            yield await self.recv()
    except ConnectionClosed as exc:
        if exc.code == 1000:
            return
        else:
            raise

Here is the code link:
https://github.com/aaugustin/websockets/blob/27549c4b390443b7504e937d4d974bd0855b4c7f/websockets/py36/protocol.py#L4

### Additional contract requirements

- `ConnectionClosedOK` and `ConnectionClosedError` are subclasses of `ConnectionClosed`.
- `ConnectionClosedOK` represents a normal closure, i.e. status code 1000 (OK) or 1001 (going away).
- `ConnectionClosedError` represents an abnormal closure, i.e. any status code other than 1000 and 1001.
- Normal closures are reported with `ConnectionClosedOK`: when a connection is closed with status code 1000, `recv()` raises `ConnectionClosedOK` rather than the base `ConnectionClosed`.
