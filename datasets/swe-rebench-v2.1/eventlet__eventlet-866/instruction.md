Greening existing locks doesn't always work right
Following https://github.com/eventlet/eventlet/commit/abbe7a5d6569b4518fbc68309175d93e9cf9081f (though I feel bad -- the problem seems most likely to be in code I wrote in an earlier version of https://github.com/eventlet/eventlet/pull/754), monkey-patching sometimes leaves lock references as empty dicts (??)

Given a simple repro script like
``` python
import unittest.mock
import eventlet
import sys

print(f'{sys.version.split()[0]=}, {eventlet.__version__=}')
print(f'{unittest.mock.NonCallableMock._lock=}')
eventlet.monkey_patch(thread=True)
print(f'{unittest.mock.NonCallableMock._lock=}')
```
(Note that `unittest.mock.NonCallableMock._lock` only exists for python>=3.10.9,!=3.11.0; see https://github.com/python/cpython/issues/98624 for some background.)

I get output like
```
sys.version.split()[0]='3.10.12', eventlet.__version__='0.34.2'
unittest.mock.NonCallableMock._lock=<unlocked _thread.RLock object owner=0 count=0 at 0x7fac882f5b00>
unittest.mock.NonCallableMock._lock={}
Segmentation fault (core dumped)
```
The segfault seems like a give-away that something is amiss; trying again with `-X dev` and `gdb` attached, it either continues to segfault during garbage collection:
```
sys.version.split()[0]='3.10.12', eventlet.__version__='0.34.2'
unittest.mock.NonCallableMock._lock=<unlocked _thread.RLock object owner=0 count=0 at 0x7ffff6c416d0>
unittest.mock.NonCallableMock._lock={}

Program received signal SIGSEGV, Segmentation fault.
0x000055555567d7eb in gc_list_remove (node=0x7ffff6c416c0) at ../Modules/gcmodule.c:273
273     ../Modules/gcmodule.c: No such file or directory.
(gdb) #0  0x000055555567d7eb in gc_list_remove (node=0x7ffff6c416c0) at ../Modules/gcmodule.c:273
#1  PyObject_GC_Del (op=0x7ffff6c416d0) at ../Modules/gcmodule.c:2369
#2  0x0000555555736bb8 in _PyDict_ClearFreeList (interp=0x555555b3e260) at ../Objects/dictobject.c:269
#3  0x000055555567e328 in clear_freelists (interp=0x555555b3e260) at ../Modules/gcmodule.c:1045
#4  gc_collect_main (tstate=0x555555b5a130, generation=2, n_collected=0x7fffffffe148, n_uncollectable=0x7fffffffe140, nofail=0) at ../Modules/gcmodule.c:1326
#5  0x0000555555785470 in gc_collect_with_callback (tstate=0x555555b5a130, generation=2) at ../Modules/gcmodule.c:1413
#6  0x00005555557b6aae in PyGC_Collect () at ../Modules/gcmodule.c:2099
#7  0x00005555557b44c0 in Py_FinalizeEx () at ../Python/pylifecycle.c:1781
#8  0x00005555557a5913 in Py_RunMain () at ../Modules/main.c:668
#9  0x000055555577c02d in Py_BytesMain (argc=<optimized out>, argv=<optimized out>) at ../Modules/main.c:720
(More stack frames follow...)
```
Or bombs our trying to get the repr for the last print:
```
sys.version.split()[0]='3.10.12', eventlet.__version__='0.34.2'
unittest.mock.NonCallableMock._lock=<unlocked _thread.RLock object owner=0 count=0 at 0x7ffff6c416d0>

Program received signal SIGSEGV, Segmentation fault.
type_getattro (type=<optimized out>, name=<optimized out>) at ../Objects/typeobject.c:3936
3936    ../Objects/typeobject.c: No such file or directory.
(gdb) #0  type_getattro (type=<optimized out>, name=<optimized out>) at ../Objects/typeobject.c:3936
#1  0x00005555556aae5a in PyObject_GetAttr (v=<type at remote 0x555555d8b950>, name='_lock') at ../Objects/object.c:932
#2  0x000055555569c971 in _PyEval_EvalFrameDefault (tstate=<optimized out>, f=<optimized out>, throwflag=<optimized out>) at ../Python/ceval.c:3592
#3  0x00005555556939c6 in _PyEval_EvalFrame (throwflag=0, f=Frame 0x555555bbe060, for file /home/tburke/repro.py, line 8, in <module> (), tstate=0x555555b5a130)
    at ../Include/internal/pycore_ceval.h:46
#4  _PyEval_Vector (tstate=0x555555b5a130, con=<optimized out>, locals=<optimized out>, args=<optimized out>, argcount=<optimized out>, kwnames=<optimized out>) at ../Python/ceval.c:5067
#5  0x0000555555789256 in PyEval_EvalCode (co=<code at remote 0x7ffff7798ee0>,
    globals={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>}, locals=<optimized out>) at ../Python/ceval.c:1134
#6  0x00005555557b4108 in run_eval_code_obj (tstate=0x555555b5a130, co=0x7ffff7798ee0,
    globals={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>},
    locals={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>}) at ../Python/pythonrun.c:1291
#7  0x00005555557ad9cb in run_mod (mod=<optimized out>, filename=<optimized out>,
    globals={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>},
    locals={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>}, flags=<optimized out>, arena=<optimized out>) at ../Python/pythonrun.c:1312
#8  0x00005555557b3e55 in pyrun_file (fp=fp@entry=0x555555b69280, filename=filename@entry='/home/tburke/repro.py', start=start@entry=257,
    globals=globals@entry={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>},
    locals=locals@entry={'__name__': '__main__', '__doc__': None, '__package__': None, '__loader__': <SourceFileLoader(name='__main__', path='/home/tburke/repro.py') at remote 0x7ffff777e710>, '__spec__': None, '__annotations__': {}, '__builtins__': <module at remote 0x7ffff7914290>, '__file__': '/home/tburke/repro.py', '__cached__': None, 'unittest': <module at remote 0x7ffff765f710>, 'eventlet': <module at remote 0x7ffff765f3b0>, 'sys': <module at remote 0x7ffff78f35f0>}, closeit=closeit@entry=1, flags=0x7fffffffe218)
    at ../Python/pythonrun.c:1208
#9  0x00005555557b3338 in _PyRun_SimpleFileObject (fp=0x555555b69280, filename='/home/tburke/repro.py', closeit=1, flags=0x7fffffffe218) at ../Python/pythonrun.c:456
(More stack frames follow...)
```
FWIW, I see similar trouble with python 3.12.1.
