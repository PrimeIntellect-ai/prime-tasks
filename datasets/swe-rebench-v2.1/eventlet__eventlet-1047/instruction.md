os.fork() doesn't work with Eventlet on Python 3.13
While trying to make nova work with python3.13, I've encountered the following bug which I could reduce to this reproducer:
```python3
import eventlet

eventlet.monkey_patch()

import threading

def background_task():
    threading._after_fork()

t = threading.Thread(target=background_task)
t.start()
t.join()
```

Here's the error output:
```shell
$ python3 reproducer.py
Exception in thread Thread-1 (background_task):
Traceback (most recent call last):
  File "/usr/lib/python3.13/threading.py", line 1566, in _after_fork
    current = _active[get_ident()]
              ~~~~~~~^^^^^^^^^^^^^
KeyError: 128691506491200

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/usr/lib/python3.13/threading.py", line 1041, in _bootstrap_inner
    self.run()
    ~~~~~~~~^^
  File "/usr/lib/python3.13/threading.py", line 992, in run
    self._target(*self._args, **self._kwargs)
    ~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/var/lib/nova/reproducer.py", line 9, in background_task
    threading._after_fork()
    ~~~~~~~~~~~~~~~~~~~~~^^
  File "/usr/lib/python3.13/threading.py", line 1571, in _after_fork
    current = _MainThread()
  File "/usr/lib/python3.13/threading.py", line 1354, in __init__
    self._handle = _make_thread_handle(self._ident)
                   ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/eventlet/green/thread.py", line 80, in _make_thread_handle
    assert ident == get_ident(greenthread)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError
```

The same snippet without eventlet works correctly:
```shell
$ python3 reproducer_threading.py
```

Error from nova that threw me into this race:
```python
Exception ignored in: <function _after_fork at 0x75fbe2136ac0>
Traceback (most recent call last):
  File "/usr/lib/python3.13/threading.py", line 1571, in _after_fork
    current = _MainThread()
  File "/usr/lib/python3.13/threading.py", line 1354, in __init__
    self._handle = _make_thread_handle(self._ident)
  File "/usr/lib/python3/dist-packages/eventlet/green/thread.py", line 80, in _make_thread_handle
    assert ident == get_ident(greenthread)
AssertionError:
```

### Additional contract requirements

- After `eventlet.monkey_patch()`, green threads that were started before `os.fork()` continue to run in the child process, and `threading.enumerate()` lists them in both the parent and the child.
