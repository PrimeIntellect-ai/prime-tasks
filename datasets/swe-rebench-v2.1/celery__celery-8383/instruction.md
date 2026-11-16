EagerResult doesn't seem to poplate name
Sometimes I run my tasks with `CELERY_TASK_ALWAYS_EAGER` to aid debugging, it seems like the `name` property of EagerResult isn't populated, which makes this sort of investigation more tricky.

I have some code I use to list my tasks in a django app, and part of this is to grab the task name.

When running eagerly, the EagerResult task status is SUCCESS, so I would have expected `name` to be available at this point.

### Additional contract requirements

- `EagerResult.__init__` in `celery/result.py` has the signature `EagerResult(id, name, ret_value, state, traceback=None)`, where `name` is the task name.
- An `EagerResult` exposes its task name through its `name` attribute, and a task executed eagerly (for example via `Task.apply`) produces an eager result whose `name` is that task's name.
