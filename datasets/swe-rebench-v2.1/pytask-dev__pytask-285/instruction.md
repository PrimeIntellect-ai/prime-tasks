ENH: Don't show tracebacks of "skipped because previous task failed" with verbosity < 2
#### Is your feature request related to a problem?

Sometimes a task fails which is required to succeed for many other tasks. Then, the report at the end of the pytask session will be crowded with tracebacks only saying which task is required to succeed for another task to be started. A user does not find this particularly important and, instead, would like to focus on the failed task.

#### Describe the solution you'd like

Don't show "skipped because previous failed" tracebacks for verbosity 0 and 1. Show them for 2.

### Additional contract requirements

- The report for a task skipped because a previous task failed is the same errored-task report used for failed tasks. It is identified by its header line `Task <task name> failed`, where `<task name>` is the task id (for example `Task task_example.py::task_second failed`).
