anta/runner.py throws unhandled exception ValueError: not allowed to raise maximum limit
This seems to be dependent on the underlying OS. Here two samples from Ubuntu (all good) and Rocky9 (fail).

Ubuntu:
```shell
$> docker run --rm python:3.12-slim python -c "import resource; print(resource.getrlimit(resource.RLIMIT_NOFILE))"
(1048576, 1048576)
$> docker run --rm python:3.12-slim python -c "import resource; resource.setrlimit(resource.RLIMIT_NOFILE, resource.getrlimit(resource.RLIMIT_NOFILE))"
$> echo $?
0
```

Rocky9:
```shell
$> docker run -rm python:3.12-slim python -c "import resource; print(resource.getrlimit(resource.RLIMIT_NOFILE))"
(1073741816, 1073741816)

$> docker run --rm python:3.12-slim python -c "import resource; resource.setrlimit(resource.RLIMIT_NOFILE, resource.getrlimit(resource.RLIMIT_NOFILE))"
Traceback (most recent call last):
  File "<string>", line 1, in <module>
ValueError: not allowed to raise maximum limit
```

[HIDDEN] But IMHO we should relay in very platform specific features.

### Additional contract requirements

- A `ValueError` raised while adjusting the open-file limit must not escape to the caller.
