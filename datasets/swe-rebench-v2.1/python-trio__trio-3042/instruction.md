Regression: unix socket bind does not work with a PathLike argument
trio.socket.SocketType.bind no longer works with a PathLike (e.g. pathlib.Path) argument.

Simple test program:
```python
import socket, trio.socket
from pathlib import Path

async def main():
    sock = trio.socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    await sock.bind(Path('/tmp/x.sock'))

trio.run(main)
```

Results in:
```
Traceback (most recent call last):
  File "/tmp/x.py", line 8, in <module>
    trio.run(main)
  File "/usr/lib/python3.12/site-packages/trio/_core/_run.py", line 2305, in run
    raise runner.main_task_outcome.error
  File "/tmp/x.py", line 6, in main
    await sock.bind(Path('/tmp/x.sock'))
  File "/usr/lib/python3.12/site-packages/trio/_socket.py", line 874, in bind
    address = await self._resolve_address_nocp(address, local=True)
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/trio/_socket.py", line 922, in _resolve_address_nocp
    return await _resolve_address_nocp(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/site-packages/trio/_socket.py", line 472, in _resolve_address_nocp
    [HIDDEN]
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError
```

This bugs seems to have been introduced in [cf1f3c745](https://github.com/python-trio/trio/commit/cf1f3c745#diff-300b958089de6b62596dad8182b7dfb234ac01d922fdbce3456f641c5a9964e1R466), released in v0.23.0.

### Additional contract requirements

- For AF_UNIX sockets, `trio.socket.SocketType.bind` must accept a valid filesystem address supplied as an `os.PathLike`, including a `pathlib.Path`, as well as string and bytes addresses.
