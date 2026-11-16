Add new "context" option to specify the multiprocessing context internally used by handlers
A better fix should be implemented for #746, because changing the default context globally using `set_start_method()` is not always suitable.

Invalid use case example on Linux (will hang forever because child processes crash):

```python
import multiprocessing
import sys

from loguru import logger


def set_logger(logger_):
    global logger
    logger = logger_


def log_test(num):
    print("before log")
    logger.info(f"hi {num}!")
    print("do we reach this?")
    logger.complete()


def main():
    logger.remove()
    logger.add(sys.stderr, enqueue=True)

    with multiprocessing.get_context("spawn").Pool(
        4, initializer=set_logger, initargs=(logger,)
    ) as pool:
        pool.map(log_test, list(range(10)))


if __name__ == "__main__":
    main()
```

Proposed solution using a new `context` attribute:

```python
import multiprocessing
import sys

from loguru import logger


def set_logger(logger_):
    global logger
    logger = logger_


def log_test(num):
    print("before log")
    logger.info(f"hi {num}!")
    print("do we reach this?")
    logger.complete()


def main():
    context = multiprocessing.get_context("spawn")
    logger.remove()
    logger.add(sys.stderr, enqueue=True, context=context)

    with context.Pool(4, initializer=set_logger, initargs=(logger,)) as pool:
        pool.map(log_test, list(range(10)))


if __name__ == "__main__":
    main()
```
