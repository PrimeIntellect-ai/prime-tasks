--profile CLI option is broken
### mkosi commit the issue has been seen with

4681dd733a925cd048d0301af26221bce0c95eed

### Used host distribution

_No response_

### Used target distribution

_No response_

### Linux kernel version used

_No response_

### CPU architectures issue was seen on

None

### Unexpected behaviour you saw

Any instance of `--profile <profilename>` as a CLI argument crashes mkosi. This happens regardless of the config files, whether or not `mkosi.profiles/profilename.conf` or `mkosi.profiles/profilename/mkosi.conf` exists.

```
mkosi --profile profilename build
```

### Used mkosi config

_No response_

### mkosi output

```sh
Traceback (most recent call last):
  File "/usr/local/bin/mkosi/mkosi/run.py", line 60, in uncaught_exception_handler
  File "/usr/lib/python3.12/contextlib.py", line 81, in inner
    return func(*args, **kwds)
           ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/bin/mkosi/mkosi/__main__.py", line 32, in main
  File "/usr/local/bin/mkosi/mkosi/config.py", line 3742, in parse_config
  File "/usr/local/bin/mkosi/mkosi/config.py", line 3670, in parse_config_one
AttributeError: 'Namespace' object has no attribute 'profile'
```
