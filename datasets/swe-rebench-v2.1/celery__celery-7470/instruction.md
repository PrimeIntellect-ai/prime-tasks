Setting task_compression value doesn't actually do anything
## Checklist
* [ ] I have included the output of ``celery -A proj report`` in the issue.
      (if you are not able to do this, then at least specify the Celery
       version affected).
       Celery==4.2.0
* [x] I have verified that the issue exists against the `master` branch of Celery.

## Steps to reproduce
```python3
app = Celery()
app.conf.update(task_compression="gzip")
```

## Expected behavior
I would expect that if I set a global `task_compression` config, my tasks are indeed gzipped. I shouldn't have to manually define compression=gzip on each task I want.

## Actual behavior
I don't think this setting is respected. This could be the wrong place to look, but it seems like `amqp` is using the wrong compression setting when sending a message: https://github.com/celery/celery/blob/7d9300b3b94399eafb5e40a08a0cdc8b05f896aa/celery/app/amqp.py#L548. [HIDDEN] - should this read [HIDDEN] ? Or am I missing something?

### Additional contract requirements

- When a task is published without an explicit compression value, use the app-wide `task_compression` configuration value.
