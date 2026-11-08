Strange behavior with `HTTPError` and multiprocessing
Hello!

We use `gcsfs` in a cloud workflow via Kubernetes VMs.

Our workflow uses `concurrent.futures` (multiprocessing). We are aware of the `fork` issues and we make sure to use the `spawn` context when we create our process pool when using `gcsfs`.

When a `gcsfs.retry.HTTPError` with a response is raised in a subprocess, while it is being forwarded to be raised by the host process, it crashes the process pool, and sometimes this causes the VM to hang. The main process sometimes crashes, but sometimes hangs. See below for a minimal reproducer.

In the main function, it calls all three functions with the process pool. First one (baseline `ZeroDivisonError`) fails as expected and raises the correct issue. The second one (`HttpError` with a response) fails with a `BrokenProcessPool` and the traceback says the `HTTPError` caused this. The third one (`HTTPError` without response) raises `HTTPError` as expected. Looking at the traceback, seems like when the `HTTPError` is being re-raised, the response has been stringified already but as you know ([here](https://github.com/fsspec/gcsfs/blob/1966d78e0cc88a1023eb7207a044ace8816b7ab4/gcsfs/retry.py#L17)) it expects a response with two fields. Not sure why/how this is breaking.

Do you have any ideas about this?

P.S. it may be too much to look at but this is how we use it:
1. Call from host process [here](https://github.com/TGSAI/mdio-python/blob/cafef57c1a35ba25135b306c5540fe270497ad4e/src/mdio/segy/blocked_io.py#L144-L168)
2. The function being called [here](https://github.com/TGSAI/mdio-python/blob/cafef57c1a35ba25135b306c5540fe270497ad4e/src/mdio/segy/_workers.py#L136)
3. The lines where `gcsfs` gets used are [here](https://github.com/TGSAI/mdio-python/blob/cafef57c1a35ba25135b306c5540fe270497ad4e/src/mdio/segy/_workers.py#L205-L208) and [here](https://github.com/TGSAI/mdio-python/blob/cafef57c1a35ba25135b306c5540fe270497ad4e/src/mdio/segy/_workers.py#L223-L226). We use Zarr's integration with `gcsfs`.

Thanks!

# Code

```python
from gcsfs.retry import HttpError
from concurrent.futures import ProcessPoolExecutor
import multiprocessing as mp
from random import random


DUMMY_RESPONSE = {
    "code": 429,
    "message": "You have exceeded your bucket's allowed rate. See https://cloud.google.com/storage/docs/hotspotting for details.",
}


def http_error_generator_with_response(_):
    proba = random()

    if proba > 0.85:
        try:
            1 / 0
        except ZeroDivisionError as e:
            raise HttpError(DUMMY_RESPONSE)


def http_error_generator_no_response(_):
    proba = random()

    if proba > 0.85:
        try:
            1 / 0
        except ZeroDivisionError as e:
            raise HttpError()


def zero_division_generator(_):
    proba = random()

    if proba > 0.85:
        try:
            1 / 0
        except ZeroDivisionError as e:
            raise e


def main():
    ctx = mp.get_context("spawn")

    with ProcessPoolExecutor(4, mp_context=ctx) as p:
        # This raises zero division error correctly.
        results = p.map(zero_division_generator, range(100))
        _ = list(results)

        # This causes a broken process pool and hangs Google cloud VMs.
        results = p.map(http_error_generator_with_response, range(100))
        _ = list(results)

        # This raises an HTTPError as expected.
        results = p.map(http_error_generator_no_response, range(100))
        _ = list(results)


if __name__ == "__main__":
    main()
```

# Traceback
<details>
<summary>Click to expand.</summary>

```python
concurrent.futures.process._RemoteTraceback:
'''
Traceback (most recent call last):
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/process.py", line 419, in wait_result_broken_or_wakeup
    result_item = result_reader.recv()
                  ^^^^^^^^^^^^^^^^^^^^
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/multiprocessing/connection.py", line 250, in recv
    return _ForkingPickler.loads(buf.getbuffer())
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/user.name/PycharmProjects/my-package/.venv/lib/python3.11/site-packages/gcsfs/retry.py", line 19, in __init__
    self.code = error_response.get("code", None)
                ^^^^^^^^^^^^^^^^^^
AttributeError: 'str' object has no attribute 'get'
'''

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/Users/user.name/PycharmProjects/my-package/gcsfs_exception_mvp.py", line 61, in <module>
    main()
  File "/Users/user.name/PycharmProjects/my-package/gcsfs_exception_mvp.py", line 53, in main
    _ = list(results)
        ^^^^^^^^^^^^^
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/process.py", line 602, in _chain_from_iterable_of_lists
    for element in iterable:
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/_base.py", line 619, in result_iterator
    yield _result_or_cancel(fs.pop())
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/_base.py", line 317, in _result_or_cancel
    return fut.result(timeout)
           ^^^^^^^^^^^^^^^^^^^
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/_base.py", line 456, in result
    return self.__get_result()
           ^^^^^^^^^^^^^^^^^^^
  File "/Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/concurrent/futures/_base.py", line 401, in __get_result
    raise self._exception
concurrent.futures.process.BrokenProcessPool: A process in the process pool was terminated abruptly while the future was running or pending.
```

</details>
