[Feature] multiple stacks deletion
**Is your feature request related to a problem? Please describe.**
It's a pain to launch the tool every time I want to delete multiple stacks.

**Describe the solution you'd like**
Allow multiple stacks to be selected.

**Additional context**
> Add any other context or screenshots about the feature request here.

### Additional contract requirements

A user can select multiple stacks for deletion in one run by giving the stack name option (`-s` / `--stackName`) more than once, e.g. `--stackName StackOne --stackName StackTwo`, and the tool processes each selected stack during that run.
