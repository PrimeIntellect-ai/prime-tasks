Add ability to exclude files from handler lookup
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Feature Proposal

## Description
Please add the ability to exclude certain files from the handler lookup.  This is to get around the extraneous (and possibly error-prone) `WARNING: More than one matching handlers found for 'handler'. Using 'handler.js'` message when there are unit test files in the same directory.

Possible config example:
```
custom:
  webpack:
    excludeFiles: src/**/*.test.[t|j]s
```

Similar or dependent issue(s):
* #405
