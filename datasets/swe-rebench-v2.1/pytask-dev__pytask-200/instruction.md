ENH: Add a `@pytask.mark.task` decorator to mark functions as tasks irrespective of the name.
#### Is your feature request related to a problem?

Currently, task functions must be prefixed with ``task_`` to be considered by pytask which is an unnecessary limitation as some user might prefer a different naming scheme.

For modules, the limitation is basically lifted since setting the configuration option [``task_files``](https://pytask-dev.readthedocs.io/en/latest/reference_guides/configuration.html#confval-task_files) to ``*`` would basically collect all files.

#### Describe the solution you'd like

A decorator `pytask.mark.task` which optionally accepts a string which is the task id of the task.

````python
@pytask.mark.task("real_task_id")
def do_this_and_only_this(depends_on, produces):
    ...
```

Then, there needs to be a small change in the collection module to also collect functions with the ``pytask.mark.task`` marker.
