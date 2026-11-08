ENH: Fix display of tasks in the ExecutionTable with default verbosity.
#### Problem description

The current implementation is faulty since we select [HIDDEN] whether we actually want to display the specific reports in the subset. [HIDDEN]

With many tasks which are skipped because they are successful one sees that the tasks which are not displayed block other valid tasks from the table.

### Additional contract requirements

- At default verbosity, reports omitted from the display must not count against the table's limit or prevent otherwise displayable tasks from appearing.
