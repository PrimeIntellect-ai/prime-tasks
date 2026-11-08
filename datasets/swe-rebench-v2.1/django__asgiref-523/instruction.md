AttributeError: asgiref.local._CVar object has no attribute 'value'
Running the latest `main` (`abc69a054aa440ef42c939b5a197df05c3ad48d2`) in production to test a fix for https://github.com/django/asgiref/issues/467, I see this error somewhat frequently across a wide spread of our requests/endpoints. This error was frequent enough that I reverted back to the old version which errors in a different way less frequently like https://github.com/django/asgiref/issues/467.

Not really sure why `__delattr__` in `_CVar` needs to throw if we try to delete an attribute that doesn't exist. Does this indicate a programming/synchronization bug somewhere or is this just a bit over-restricting? Not sure if this is bug prevention or its just fine.

Happy to test any further improvements/fixes here to try and get a release which doesn't have errors. Can also provide any additional info that might be helpful here if need be.

Relevant versions:
```
    "ddtrace==2.9.2",
    "django==4.2.13",
```

Stack trace (all failures are basically the same):

```
AttributeError: <asgiref.local._CVar object at 0x7f05030333a0> object has no attribute 'value'
  File "django/core/handlers/asgi.py", line 160, in __call__
    await self.handle(scope, receive, send)
  File "django/core/handlers/asgi.py", line 190, in handle
    await self.send_response(response, send)
  File "django/core/handlers/asgi.py", line 296, in send_response
    await sync_to_async(response.close, thread_sensitive=True)()
  File "concurrent/futures/thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
  File "ddtrace/contrib/futures/threading.py", line 36, in _wrap_execution
    return fn(*args, **kwargs)
  File "django/http/response.py", line 335, in close
    signals.request_finished.send(sender=self._handler_class)
  File "django/dispatch/dispatcher.py", line 176, in send
    return [
  File "django/dispatch/dispatcher.py", line 177, in <listcomp>
    (receiver, receiver(signal=self, sender=sender, **named))
  File "django/core/handlers/base.py", line 370, in reset_urlconf
    set_urlconf(None)
  File "django/urls/base.py", line 137, in set_urlconf
    del _urlconfs.value
  File "asgiref/local.py", line 129, in __delattr__
    delattr(storage, key)
  File "asgiref/local.py", line 38, in __delattr__
    raise AttributeError(f"{self!r} object has no attribute {key!r}")
```
