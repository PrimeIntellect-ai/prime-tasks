gh ru with github enterprise does not work
### Describe the bug

Similar bug mentioned https://github.com/cli/cli/issues/3437, but gh run view or list all return a 404. The URL returned seems right based on REST api docs but not getting any response. When comparing the ID `gh run list` doesn't seem to be correct based on the ids from `gh workflow list`

**gh cli version:** `gh version 2.63.2 (2024-12-05)`
**ghe version:** `3.13.4`

### Steps to reproduce the behavior

1. Complete login to the enterprise server with Github CLI
2. Go to a repository directory that uses that server as a remote
3. Run gh run list returns 404

### Expected vs actual behavior

The gh run list prints out list of workflow runs for the repo to choose from

### Logs

```bash
[git remote -v]
[git config --get-regexp ^remote\..*\.gh-resolved$]
* Request at 2024-12-13 00:23:19.723417 -0600 CST m=+0.101249251
* Request to https://{SERVER_URL}/api/graphql
* Request took 281.385ms
⣾* Request at 2024-12-13 00:23:20.040818 -0600 CST m=+0.418510918
* Request to https://{SERVER_URL}/api/v3/repos/{ORG}/{REPO}/actions/runs?per_page=20&exclude_pull_requests=true
⢿* Request took 421.362291ms
⡿* Request at 2024-12-13 00:23:20.534045 -0600 CST m=+0.911535293
* Request to https://{SERVER_URL}/api/v3/repos/{ORG}/{REPO}/actions/workflows?per_page=100&page=1
⣟* Request took 105.218541ms
* Request at 2024-12-13 00:23:20.700194 -0600 CST m=+1.077616418
* Request to https://{SERVER_URL}/api/v3/repos/{ORG}/{REPO}/actions/workflows/63737
⣯* Request took 121.476458ms
failed to get runs: HTTP 404: Not Found (https://{SERVER_URL}/api/v3/repos/{ORG}/{REPO}/actions/workflows/63737)
```

### Additional contract requirements

- When a workflow run is listed but its workflow name cannot be retrieved because the workflow endpoint returns HTTP 404, leave the WORKFLOW column blank for that run.
