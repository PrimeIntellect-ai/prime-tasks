Error in solver tee output on Windows
## Summary

When I an solving a pyomo problem and use the "tee=True" option, and I scroll up in the CMD window on Windows to see some output displayed above, I often get the error below.

```sh
Number of objective function evaluations             = 30
Number of objective gradient evaluations             = 6
Number of equality constraint evaluations            = 31
Number of inequality constraint evaluations          = 0
Number of equality constraint Jacobian evaluations   = 6
Number of inequality constraint Jacobian evaluations = 0
Number of Lagrangian Hessian evaluations             = 5
Total CPU secs in IPOPT (w/o function evaluations)   =      0.668
Total CPU secs in NLP function evaluations           =     25.060

EXIT: Optimal Solution Found.
    solver.solve(m, tee=True)
  File "c:\users\eslickj\git\pyomo\pyomo\opt\base\solvers.py", line 578, in solve
    _status = self._apply_solver()
  File "c:\users\eslickj\git\pyomo\pyomo\opt\solver\shellcmd.py", line 246, in _apply_solver
    self._rc, self._log = self._execute_command(self._command)
  File "c:\users\eslickj\git\pyomo\pyomo\opt\solver\shellcmd.py", line 324, in _execute_command
    t.STDERR.flush()
  File "c:\users\eslickj\git\pyomo\pyomo\common\tee.py", line 390, in __exit__
    self.close(et is not None)
  File "c:\users\eslickj\git\pyomo\pyomo\common\tee.py", line 378, in close
    raise RuntimeError(
RuntimeError: TeeStream: deadlock observed joining reader threads
```

### Steps to reproduce the issue

I'm not sure this happens 100% of the time, but you just need to run a pyomo problem on windows in a cmd window and be scrolling up when the solver completes.

It's not with a specific script.  It happens with with any problem I run.  Should be reproducible with any problem using ipopt and "tee=True."

### Error Message

```
  File "c:\users\eslickj\git\pyomo\pyomo\common\tee.py", line 378, in close
    raise RuntimeError(
RuntimeError: TeeStream: deadlock observed joining reader threads
```

### Information on your system

Pyomo version: Pyomo 6.0.2 (devel {string_args}) (CPython 3.9.4 on Windows 10)
Python version:  3.9.4
Operating system: Windows 10
How Pyomo was installed (PyPI, conda, source): source (pip with -e option)
Solver (if applicable): Ipopt

### Additional contract requirements

- If a stream passed to `TeeStream` stops accepting output temporarily (for example, while a Windows console is being scrolled), `TeeStream` must not report a deadlock. The `write()` call of the destination may block for at least 8 seconds before it returns; `TeeStream` must wait for it to finish and then deliver all pending output to the destination, and the context manager must exit without error.
