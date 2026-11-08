npm lookup failure should be error if lock file present
Particularly important for onboarding. Currently it warns for modules it can't look up but when lock files are present this causes all updates within the package file to fail.

### Additional contract requirements

- When an npm dependency lookup fails and a lock file is present, the error message must be exactly `Failed to look up dependency. This will block *all* dependencies from being updated due to presence of lock file.`
