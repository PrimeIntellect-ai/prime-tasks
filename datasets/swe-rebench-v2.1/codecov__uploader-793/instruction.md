Slug Parser doesn't parse ssh:// urls
**Describe the bug**
Our git remote is of the form `ssh://git@<host:port>/repo.git`
When using the uploader, the remote url parser [HIDDEN]
This causes the slug to start with `//` and then the uploader fails with the following:

```
[2022-06-03T15:17:49.918Z] ['error'] There was an error running the uploader: Error uploading to https://codecov.io: Error: There was an error fetching the storage URL during POST: 400 - Invalid request parameters
[2022-06-03T15:17:49.919Z] ['verbose'] The error stack is: Error: Error uploading to https://codecov.io: Error: There was an error fetching the storage URL during POST: 400 - Invalid request parameters
    at main (/snapshot/repo/dist/src/index.js)
    at processTicksAndRejections (node:internal/process/task_queues:96:5)
[2022-06-03T15:17:49.919Z] ['verbose'] End of uploader: 3102 milliseconds
```

**To Reproduce**
Steps to reproduce the behavior:
1. Create a git repo.
2. Set the remote to be of the form `ssh://git@<host:port>/repo.git`
3. Collect coverage data and try to upload it

**Expected behavior**
Coverage upload should succeed.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

For a remote of the reported `ssh://` form, including a port in its authority, the uploader must identify the repository slug from the path (for example, `codecov/uploader` for `/codecov/uploader.git`) and complete the coverage upload successfully.
