Use config's signac_version to track schema version for easier migration.
### Feature description

Currently it appears that we have an implied Project config value, `'signac_version': (0, 1, 0)`.
https://github.com/glotzerlab/signac/blob/ba14a1b60c7ba431d8c8e54d6909203248cccca9/signac/common/validate.py#L55

### Proposed solution

We should update the configuration to store the actual version of signac used to create or initialize the project. This will make migrations easier and make something of this currently unused config value. We explicitly have backward compatibility to 0.1.0 already so this won't break anything.

### Additional contract requirements

The version recorded in the project configuration is the data-model schema
version (``schema_version``), exposed as ``signac.version.SCHEMA_VERSION``; it is
not the signac package version.
