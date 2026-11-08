Asyncio loop not cleared on closing / garbage collection
## Bug Description

We have a use case where we create connectors on demand from users to connect to Cloud SQL. This implies that we create a `Connector` instance and then `close()` it. After that, the reference to the connector no longer exists so Python GC it.

The issue we see is the exception `OSError`: `[Errno 24] Too many open files` raised at the creation of a connector after a long time. Especially, it is when the asyncio loop is created (see below the stacktrace).

## Example code

```python
with Connector(credentials=credentials) as connector:
    try:
        yield connector.connect(
            self.authentication.instance,
            "pg8000",
            user=self.authentication.username,
            password=self.authentication.password,
            db=self.authentication.database,
        )
        break
    except GoogleAPICallError:
        raise IssueException()
    except ClientResponseError as e:
        if e.status == 429:
            time.sleep(5)
            continue
        else:
            raise IssueException()

```

## Stacktrace
```
OSError: [Errno 24] Too many open files
  File "salescrew/core/celery.py", line 146, in __call__
    raise e
  File "salescrew/core/celery.py", line 143, in __call__
    self.run(*args, **kwargs)
  File "salescrew/connectors/routines.py", line 153, in update_users_from_integrations
    integration_user = connector.get_user(user_integration.id)
  File "salescrew/connectors/databases/postgresql.py", line 297, in get_user
    with self.connection as conn:
  File "contextlib.py", line 135, in __enter__
    return next(self.gen)
  File "salescrew/connectors/databases/postgresql.py", line 346, in connection
    connector = Connector(credentials=credentials)
  File "/usr/local/lib/python3.10/site-packages/google/cloud/sql/connector/connector.py", line 67, in __init__
    self._loop: asyncio.AbstractEventLoop = asyncio.new_event_loop()
  File "asyncio/events.py", line 782, in new_event_loop
    return get_event_loop_policy().new_event_loop()
  File "asyncio/events.py", line 673, in new_event_loop
    return self._loop_factory()
  File "asyncio/unix_events.py", line 64, in __init__
    super().__init__(selector)
  File "asyncio/selector_events.py", line 56, in __init__
    self._make_self_pipe()
  File "asyncio/selector_events.py", line 103, in _make_self_pipe
    self._ssock, self._csock = socket.socketpair()
  File "socket.py", line 607, in socketpair
    a, b = _socket.socketpair(family, type, proto)
```

## How to reproduce

  1. Create a lot of connectors one after another

## Environment

1. OS type and version:  Linux 5.15.55-1-lts
2. Python version: Python 3.10.4
2. Connector version: 0.6.2

## Proposal of resolution

I think because the connector uses the `run_forever` method of the loop, it doesn't clear itself after. [HIDDEN]

### Additional contract requirements

- Add a public method `Connector.close(self)` in module
  `google/cloud/sql/connector/connector.py`. Calling it cleanly terminates the
  connector's background thread, guaranteeing that no lingering thread remains
  after the call, and releases the event loop's resources so that repeatedly
  creating and closing connectors does not leak open file descriptors.
