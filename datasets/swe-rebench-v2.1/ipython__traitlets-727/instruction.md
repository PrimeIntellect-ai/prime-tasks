Logging errors on Application teardown
When using `traitlets` `5.2.0` to [test](https://dev.azure.com/conda-forge/feedstock-builds/_build/results?buildId=505255&view=logs&j=656edd35-690f-5c53-9ba3-09c10d0bea97&t=e5c8ab1d-8ff9-5cae-b332-e15ae582ed2d&l=2525) `jupyterlab` [`3.4.1`](https://github.com/conda-forge/jupyterlab-feedstock/pull/333):

```bash
2022-05-12T14:07:44.4320758Z + jupyter server extension list
2022-05-12T14:07:45.0244467Z Config dir: /home/conda/.jupyter
2022-05-12T14:07:45.0246143Z
2022-05-12T14:07:45.5231596Z Config dir: $SRC/etc/jupyter
2022-05-12T14:07:45.5234278Z     jupyterlab enabled
2022-05-12T14:07:45.5235478Z     - Validating jupyterlab...
2022-05-12T14:07:45.5236604Z       jupyterlab 3.4.1 OK
2022-05-12T14:07:45.5237684Z     nbclassic enabled
2022-05-12T14:07:45.5238759Z     - Validating nbclassic...
2022-05-12T14:07:45.5239837Z       nbclassic  OK
2022-05-12T14:07:45.5240939Z     notebook_shim enabled
2022-05-12T14:07:45.5242021Z     - Validating notebook_shim...
2022-05-12T14:07:45.5243086Z       notebook_shim  OK
2022-05-12T14:07:45.5244219Z
2022-05-12T14:07:45.5260353Z Config dir: /usr/local/etc/jupyter
2022-05-12T14:07:45.5262066Z
2022-05-12T14:07:45.5601412Z Exception ignored in: <function Application.__del__ at 0x7fb85d73f760>
2022-05-12T14:07:45.5602339Z Traceback (most recent call last):
2022-05-12T14:07:45.5604678Z   File "$SRC/lib/python3.10/site-packages/traitlets/config/application.py", line 955, in __del__
2022-05-12T14:07:45.5607082Z   File "$SRC/lib/python3.10/site-packages/traitlets/config/application.py", line 945, in close_handlers
2022-05-12T14:07:45.5609436Z   File "$SRC/lib/python3.10/site-packages/traitlets/traitlets.py", line 683, in __get__
2022-05-12T14:07:45.5611694Z   File "$SRC/lib/python3.10/site-packages/traitlets/traitlets.py", line 657, in get
2022-05-12T14:07:45.5613965Z   File "$SRC/lib/python3.10/site-packages/traitlets/traitlets.py", line 1428, in _notify_observers
2022-05-12T14:07:45.5616640Z   File "$SRC/lib/python3.10/site-packages/traitlets/config/application.py", line 273, in _observe_logging_default
2022-05-12T14:07:45.5619022Z   File "$SRC/lib/python3.10/site-packages/traitlets/config/application.py", line 278, in _configure_logging
2022-05-12T14:07:45.5620968Z   File "$SRC/lib/python3.10/logging/config.py", line 810, in dictConfig
2022-05-12T14:07:45.5622663Z   File "$SRC/lib/python3.10/logging/config.py", line 547, in configure
2022-05-12T14:07:45.5624039Z ValueError: Unable to configure formatter 'console'
```

These errors are not present when testing (locally) with `traitlets 5.1.1`... will investigate further, but might be the weekend.

### Additional contract requirements

- `traitlets.config.application.Application` provides a public method `close_handlers()`.
- The application tracks whether its logging has been configured.
- After logging has been configured, `close_handlers()` closes each of the application's log handlers, suppressing any exception raised while closing, and then treats logging as no longer configured.
- Before logging has been configured, `close_handlers()` does nothing.
