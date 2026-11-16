WARNING: Field list ends without a blank line; unexpected unindent
The `WARNING: Field list ends without a blank line; unexpected unindent` has returned in 1.21.5. I suspect this is another variation on the problem reported and fixed in #293.

GitHub Actions log showing this failure: https://github.com/lsst-sqre/safir/actions/runs/3963428111/jobs/6791355176

Example docstring that produces the first error message there:

```python
    """Run the decorated function with `asyncio.run`.

    Intended to be used as a decorator around an async function that needs to
    be run in a sync context.  The decorated function will be run with
    `asyncio.run` when invoked.  The caller must not already be inside an
    asyncio task.

    Parameters
    ----------
    f
        The function to wrap.

    Examples
    --------
    An application that uses Safir and `Click`_ may use the following Click
    command function to initialize a database.

    .. code-block:: python

       import structlog
       from safir.asyncio import run_with_asyncio
       from safir.database import initialize_database

       from .config import config
       from .schema import Base


       @main.command()
       @run_with_asyncio
       async def init() -> None:
           logger = structlog.get_logger(config.safir.logger_name)
           engine = await initialize_database(
               config.database_url,
               config.database_password,
               logger,
               schema=Base.metadata,
           )
           await engine.dispose()
    """
```

Removing the `Parameters` section makes the warning go away. The same docstring (and the others in this package) worked correctly with 1.21.1.
