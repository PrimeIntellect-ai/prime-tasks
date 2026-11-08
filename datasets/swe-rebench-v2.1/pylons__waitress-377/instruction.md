Possible race condition leading to the main loop dying?
I just might be wrong because if this indeed a race condition it should be breaking more things. Anyway, I got this exception (line numbers might be wrong due to debug statements):

```py
Traceback (most recent call last):
  File "/usr/lib/python3.8/threading.py", line 932, in _bootstrap_inner
    self.run()
  File "/.../lib/python3.8/site-packages/aqt/mediasrv.py", line 89, in run
    self.server.run()
  File "/.../lib/python3.8/site-packages/waitress/server.py", line 323, in run
    self.asyncore.loop(
  File "/.../lib/python3.8/site-packages/waitress/wasyncore.py", line 285, in loop
    poll_fun(timeout, map)
  File "/.../lib/python3.8/site-packages/waitress/wasyncore.py", line 211, in poll
    r, w, e = select.select(r, w, e, timeout)
OSError: [Errno 9] Bad file descriptor
```

This error was extremely rare but since I was getting it while running tests I could just run a lot of them until one failed, which I did, and I think the problem is a follows.

1. First, thread `Thread-1` that the app I'm testing is launching, one that runs waitress server, assembles the descriptor lists for `select`: https://github.com/Pylons/waitress/blob/603d2c12ce09fcd1be0b7a5734b4fca339820286/src/waitress/wasyncore.py#L154-L166

1. [HIDDEN]

   Stack of `waitiress-0` at the moment:

   ```python
     File "/usr/lib/python3.8/threading.py", line 890, in _bootstrap
       self._bootstrap_inner()
     File "/usr/lib/python3.8/threading.py", line 932, in _bootstrap_inner
       self.run()
     File "/usr/lib/python3.8/threading.py", line 870, in run
       self._target(*self._args, **self._kwargs)
     File "/.../lib/python3.8/site-packages/waitress/task.py", line 84, in handler_thread
       task.service()
     File "/.../lib/python3.8/site-packages/waitress/channel.py", line 426, in service
       task.service()
     File "/.../lib/python3.8/site-packages/waitress/task.py", line 168, in service
       self.execute()
     File "/.../lib/python3.8/site-packages/waitress/task.py", line 451, in execute
       self.channel.write_soon(app_iter)
     File "/.../lib/python3.8/site-packages/waitress/channel.py", line 377, in write_soon
       (flushed, exception) = self._flush_exception(self._flush_some)
     File "/.../lib/python3.8/site-packages/waitress/channel.py", line 132, in _flush_exception
       return (flush(), False)
     File "/.../lib/python3.8/site-packages/waitress/channel.py", line 270, in _flush_some
       num_sent = self.send(chunk)
     File "/.../lib/python3.8/site-packages/waitress/wasyncore.py", line 479, in send
       self.handle_close()
     File "/.../lib/python3.8/site-packages/waitress/channel.py", line 317, in handle_close
       wasyncore.dispatcher.close(self)
     File "/.../lib/python3.8/site-packages/waitress/wasyncore.py", line 519, in close
       traceback.print_stack()
   ```

1.  Then, thread `Thread-1` is trying to see if the file descriptor of the socked closed above is writable, which leads to the the exception above: https://github.com/Pylons/waitress/blob/603d2c12ce09fcd1be0b7a5734b4fca339820286/src/waitress/wasyncore.py#L171-L177

Python 3.8.10, waitress 2.1.1, Ubuntu 20.04 LTS focal @ WSL2

### Additional contract requirements

- When a worker thread flushes buffered response data and the peer has disconnected, that flush must not close the connection's socket, so that the main loop can keep polling the descriptor without error.
