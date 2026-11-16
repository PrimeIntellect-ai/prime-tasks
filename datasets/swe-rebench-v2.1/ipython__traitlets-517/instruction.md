Use Parent Log If Exists
I'd like to see the default `log` attribute of a `LoggingConfigurable` be the parent log, rather than the global traitlets log, if the parent is also a LoggingConfigurable.

```python
class LoggingConfigurable(...):
    ...

    log = Instance('logging.Logger')
    @default('log')
    def _log_default(self):
        # (vvv) new behavior (vvv)
        [HIDDEN]
        # (^^^) new behavior (^^^)
        from traitlets import log
        return log.get_logger()
```

If that sounds okay I can open a merge request with those two lines added.

### Additional contract requirements

- When a `LoggingConfigurable` has a parent that is also a `LoggingConfigurable`, its default `log` value should be the parent's `log`.
