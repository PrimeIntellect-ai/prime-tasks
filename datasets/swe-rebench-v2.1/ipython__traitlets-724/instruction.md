KeyError in get_default_logging_config
If sys.executable is set to pythonw.exe calling get_default_logging_config results in a KeyError because it tries to delete a key that doesn't exist.

https://github.com/ipython/traitlets/blob/main/traitlets/config/application.py#L259

```
2022-05-12 15:42:05,811 - ERROR :   File "C:\Users\tony\miniconda3\envs\py39-7165\lib\site-packages\traitlets\config\application.py", line 259, in get_default_logging_config
2022-05-12 15:42:05,812 - ERROR :     del config["handlers"]["loggers"]
2022-05-12 15:42:05,812 - ERROR : KeyError: 'loggers'

### Additional contract requirements

- When `sys.executable` names a `pythonw.exe` executable, `get_default_logging_config()` must return a config with neither top-level `handlers` nor `loggers` keys.
- Otherwise, `get_default_logging_config()` must return a config with both top-level `handlers` and `loggers` keys.
