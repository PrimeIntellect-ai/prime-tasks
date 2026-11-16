POEM 097: Duplicate Problem names should warn, not raise.
### Desired capability or behavior.

With the recent POEM 097 related changes, output directories are either automatically named...or the user can impart a particular name so that the outputs are always saved to the same directory.

For scripts this is fine, but in the context of notebooks, rerunning a cell over and over again will result in numerous output directories.

The manual way to circumvent this is to change the "duplicate problem name" error to a warning.

In addition, we should look for ways to make this behavior the default in a notebook environment so that the user doesn't have to manually specify a name.

### Associated POEM

097

### Additional contract requirements

- A duplicate Problem name must issue an `OpenMDAOWarning` rather than raising an error.
- Attempting to activate a report that is already active for a given instance must issue an `OpenMDAOWarning` rather than raising an error.
- `OpenMDAOWarning` is a public warning class in `openmdao.utils.om_warnings`.
- The duplicate-name warning message must include the exact text `The problem name '<name>' already exists`, with the duplicate Problem name substituted for `<name>`.
- When the `scaling` report is already active, the warning message must follow the exact format `A report with the name 'scaling' for instance '<instance id>' is already active.`
