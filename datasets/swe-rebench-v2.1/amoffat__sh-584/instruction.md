sh.which doesn't return an object and doesn't throw exceptions
Hi,
I experience this unexpected behavior:
Is this a bug, or am I doing something wrong?

Python Version:
```bash
$ python --version
Python 3.9.5
```
sh Version: 1.14.2

Code snippet:

```python
 try:
      # i expect behavior as described here:
      # https://amoffat.github.io/sh/sections/exit_codes.html
      output = sh.which('xxxxx')
      # output returns a string or None , not an object
      # print(output.exit_code) fails because neither 'str' nor 'None'  has the attribute 'exit_code'
 except ErrorReturnCode:
      # this exception is not thrown
      logger.error("program not found")
```

### Additional contract requirements

- Additionally, `sh.which(program, _env=env)` must search for `program` using the `PATH` value in `env`.
