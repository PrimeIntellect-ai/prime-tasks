Skip sessions that want to use 32-bit Python on non-Windows
The current experience is not a good one:

```
$ nox -s unit-3.5-32 -r
nox > Running session unit-3.5-32
nox > Session unit-3.5-32 raised exception RuntimeError("Locating 32-bit Python ('3.5-32') is only supported on Windows.")
Traceback (most recent call last):
  File ".../.pyenv/versions/3.7.0/lib/python3.7/site-packages/nox/sessions.py", line 295, in execute
    self._create_venv()
  File ".../.pyenv/versions/3.7.0/lib/python3.7/site-packages/nox/sessions.py", line 281, in _create_venv
    self.venv.create()
  File ".../.pyenv/versions/3.7.0/lib/python3.7/site-packages/nox/virtualenv.py", line 209, in create
    cmd.extend(["-p", self._resolved_interpreter])
  File ".../.pyenv/versions/3.7.0/lib/python3.7/site-packages/nox/virtualenv.py", line 165, in _resolved_interpreter
    raise self._resolved
RuntimeError: Locating 32-bit Python ('3.5-32') is only supported on Windows.
nox > Session unit-3.5-32 failed.
```
