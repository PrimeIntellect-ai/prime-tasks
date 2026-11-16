Add support for running a file with pyflyby's py --debug (PyInf#11219)
This is a request for adding support for running file in debugger through [pyflyby's py program](https://github.com/deshaw/pyflyby/blob/master/lib/python/pyflyby/_py.py).

Say I have a file, which I want to run inside a debugger.

```
$ cat ~/tmp/helloworld.py

if __name__ == "__main__":
    print("Hello world!")

```
Today, it fails with `py`

```
$ pyflyby/bin/py --debug ~/tmp/helloworld.py

TypeError                                 Traceback (most recent call last)
File /usr/local/python/python-3.10/std/lib64/python3.10/site-packages/pyflyby/_dbg.py:524, in debugger(*args, **kwargs)
    522     return
    523 if not isinstance(arg, FrameType):
--> 524     raise TypeError(
    525         "debugger(): expected a frame/traceback/str/code; got %s"
    526         % (arg,))
    527 frame = arg
    528 if globals is not None or locals is not None:

TypeError: debugger(): expected a frame/traceback/str/code; got (PythonBlock('#!/usr/local/bin/python3\n\nif __name__ == "__main__":\n    print("Hello world!")\n\n', filename='/u/barnet/tmp/helloworld.py', flags=0x1e0000), {'__name__': '__main__', '__builtin__': <module 'builtins' (built-in)>, '__builtins__': <module 'builtins' (built-in)>, '__file__': '/u/barnet/tmp/helloworld.py'})
> /usr/local/python/python-3.10/std/lib64/python3.10/site-packages/pyflyby/_dbg.py(524)debugger()
    522         return
    523     if not isinstance(arg, FrameType):
--> 524         raise TypeError(
    525             "debugger(): expected a frame/traceback/str/code; got %s"
    526             % (arg,))

ipdb>

```

We would like `py` to work with file as well (similar to `pyflyby/bin/py -m ipdb ~/tmp/helloworld.py`).
