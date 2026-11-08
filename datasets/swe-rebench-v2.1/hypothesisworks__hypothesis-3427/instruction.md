Error with Django parallel test runner: hypothesis.errors.DeadlineExceeded is unpickleable
```
<snip>
  File "/usr/lib/python3.8/unittest/suite.py", line 122, in run
    test(result)
  File "/root/apps/netdb_demo/lib/python3.8/site-packages/hypothesis/extra/django/_impl.py", line 47, in __call__
    return unittest.TestCase.__call__(self, result)
  File "/usr/lib/python3.8/unittest/case.py", line 736, in __call__
    return self.run(*args, **kwds)
  File "/usr/lib/python3.8/unittest/case.py", line 684, in run
    self._feedErrorsToResult(result, outcome.errors)
  File "/usr/lib/python3.8/unittest/case.py", line 602, in _feedErrorsToResult
    result.addError(test, exc_info)
  File "/root/apps/netdb_demo/lib/python3.8/site-packages/django/test/runner.py", line 197, in addError
    self.check_picklable(test, err)
  File "/root/apps/netdb_demo/lib/python3.8/site-packages/django/test/runner.py", line 130, in check_picklable
    self._confirm_picklable(err)
  File "/root/apps/netdb_demo/lib/python3.8/site-packages/django/test/runner.py", line 104, in _confirm_picklable
    pickle.loads(pickle.dumps(obj))
  File "/root/apps/netdb_demo/lib/python3.8/site-packages/tblib/pickling_support.py", line 26, in unpickle_exception
    inst = func(*args)
TypeError: __init__() missing 1 required positional argument: 'deadline'
```
This happens because Exception by default reduces to arguments passed to its `__init__`, and DeadlineExceeded (and FailedHealthCheck, afaict) changes the signature when calling `super().__init__`.

[HIDDEN]
