Do not call `asyncio.get_event_loop()` if no existing event loop
As described in https://docs.python.org/3/library/asyncio-eventloop.html , directly calling `asyncio.get_event_loop()` raises DeprecationWarning if no event loop is already running. The behavior of `get_event_loop()` was changed in Python 3.10.

Up to Python 3.9, `get_event_loop()` will silently create an event loop with no warnings.

_It seems that_ in Python 3.10 and 3.11, `get_event_loop()` will still create an event loop, but a DeprecationWarning is raised.

The `get_event_loop()` behavior will change completely in Python 3.12, no longer creating an event loop but will raise an Error instead.

We must parse the code and ensure that `get_event_loop()` expecting an implicit event loop creation are removed from the code.

### Additional contract requirements

- Add a function `_get_or_new_eventloop()` in module `aiosmtpd` that takes no arguments and returns an `asyncio.AbstractEventLoop`. When an event loop is already available it returns that loop; when no event loop is available it creates a new event loop and installs it as the current event loop.
