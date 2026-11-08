convert_os_errors error when converting errno.ENAMETOOLONG to PathError
Using convert_os_errors to convert errno.ENAMETOOLONG to PathError results in unexpected keyword arguement 'exc' error. [HIDDEN]

The following example code:
```
import errno
from fs.error_tools import convert_os_errors
from fs import errors as fserrors

try:
	from fs import open_fs
	f = open_fs('/tmp')
	f.open('x'*500, mode='w')
except OSError as e:
    with convert_os_errors("foo", "test"):
        raise e
```
results in: TypeError: __init__() got an unexpected keyword argument 'exc'

### Additional contract requirements

- `PathError(path, msg=None, exc=None)`: when `msg` is supplied, `str(error)` returns that message unchanged; when `msg` is omitted, `str(error)` returns the default message `path '<path>' is invalid`, with `<path>` replaced by the supplied path.
- `ResourceNotFound(path, msg=None, exc=None)`: when `msg` is supplied, `str(error)` returns that message unchanged; when `msg` is omitted, `str(error)` returns the default message `resource '<path>' not found`, with `<path>` replaced by the supplied path.
