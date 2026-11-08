Ignore checks per workspace
**Is your feature request related to a problem? Please describe.**
There is no way to ignore a check for a specific workspace.

**Describe the solution you'd like**
Same as the `--tfvars-file`, I'd like to be able to ignore a test in an environment but not on another maybe via flags or by taking into account the current workspace.

**Describe alternatives you've considered**
No alternatives have been considered.

**Additional context**
It's common to use workspaces to manage different environments. One may want to ignore a test (i.e.`GCP009`) in staging but not in production.

Right now, by adding the (i.e.) `#tfsec:ignore:GCP009` to the tf code it'll be applied to every workspace, creating a situation where you are forced to have a staging/production parity environment, which not everyone wants to.

### Additional contract requirements

Users can identify the workspace being scanned with the `--workspace` option. An ignore may be qualified with `:ws:<WORKSPACE_NAME>` after its check identifier; it suppresses that check only for the matching workspace, and the check remains reportable in other workspaces.
