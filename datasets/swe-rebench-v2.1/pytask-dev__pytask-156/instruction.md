ENH: Add switch to display errors immediately during the execution.
#### Is your feature request related to a problem?

The problem is that you sometimes have long running tasks and when an error happens you immediately want to see the information without waiting for the other tasks to finish.

Current solutions are:

- Using the `-x` flag to immediately abort execution, but in a parallel mode it waits for the other tasks. Same with `KeyboardInterrupt`.
- Multiple pytask sessions for each task which could lead to errors when the database is changed at the same time.

#### Describe the solution you'd like

A switch which prints the usual error report known from the execution logger during the execution.

### Additional contract requirements

The command-line switch `--show-errors-immediately` enables immediate error reporting: when a task fails, display its usual error report before other tasks have finished. If the switch is omitted, report errors using the ordinary execution logger behavior.
