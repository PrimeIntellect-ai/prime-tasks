Regression in 3.1.0: Error: Cannot use 'in' operator to search for '' in false
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

3.1.0

### Plugin version

_No response_

### Node.js version

??? whatever your action pulls

### Operating system

Linux

### Operating system version (i.e. 20.04, 11.3, 10)

20.04

### Description

A basic use-case in my repository stopped working after dependabot bumped it from 3.0.2 to 3.1.0.  An error message reads `Error: Cannot use 'in' operator to search for '' in false`.  The only place that I see `false` in the output is for the default argument of the `approve-only` option.  Please see the relevant run: https://github.com/richardsheridan/trio-parallel/runs/5859944536?check_suite_focus=true#step:2:7

### Steps to Reproduce

I don't think my workflow and settings are anything extraordinary but it is the only steps to reproduce that I have:

https://github.com/richardsheridan/trio-parallel/blob/e9d713c3b86434d8bc9f9a528e0017cdb49f4aa3/.github/workflows/ci.yml#L265-L277



### Expected Behavior

_No response_

### Additional contract requirements

- `getModuleVersionChanges(prDiff)` in `src/moduleVersionChanges.js` returns an empty object `{}` when the diff contains no `package.json` changes.
- When the pull request diff contains no `package.json` changes, the action approves and merges the pull request.
