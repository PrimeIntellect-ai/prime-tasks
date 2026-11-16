[Bug]: PyBaMM fails to import when user has already imported a library that uses `mp.set_start_method`
### PyBaMM Version

develop

### Python Version

3.11

### Describe the bug

PyBaMM fails to import when importing a library that uses multiprocessing and has already set the start method to something other than fork, as a result of #3975. This should be apparent when reading the documentation for `mp.set_start_method`

Pending a long-term solution, I think that #3975 should at least have [HIDDEN] -- most people, most of the time, do not really need the multiprocessing functionality, and I don't think pybamm should force those users to modify their multiprocessing configuration. It can throw a warning saying multiprocessing is not available or whatever.

Other solutions are welcome, of course.


### Steps to Reproduce

module `thing`:
```
import multiprocessing as mp

mp.set_start_method("spawn")

def hello():
    print("hello, world")
```

script:
```
import thing
import pybamm
```

### Relevant log output

```shell
❯ python main.py
Traceback (most recent call last):
  File "/Users/abills/.../main.py", line 2, in <module>
    import pybamm
  File "/Users/abills/.../python3.11/site-packages/pybamm/__init__.py", line 204, in <module>
    from .solvers.base_solver import BaseSolver
  File "/Users/abills/.../python3.11/site-packages/pybamm/solvers/base_solver.py", line 18, in <module>
    mp.set_start_method("fork")
  File "/Users/abills/.../python3.11/multiprocessing/context.py", line 247, in set_start_method
    raise RuntimeError('context has already been set')
RuntimeError: context has already been set
```
