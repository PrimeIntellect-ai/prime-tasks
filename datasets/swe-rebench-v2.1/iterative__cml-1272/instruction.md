Move `REPO_TOKEN` to `CML_` environment variable namespace
Use `CML_TOKEN` (or similar, e.g. `CML_CI_TOKEN` etc.) instead of `REPO_TOKEN` to

- avoid potential namespace clashes
- better reflect that it could be a project token, org token, bot token, encoded username & password, etc
- better reflect that it's mostly used to *launch* runners and also is used *by* runners

---

- from https://github.com/iterative/cml.dev/pull/122#issuecomment-941330742
- related #738, #741, #712

### Additional contract requirements

- The driver token is read from the `CML_DRIVER_TOKEN` environment variable.
- The global CLI option is `--driver-token` (a string), with `--token` as its alias, described as `CI driver personal/project access token (PAT)`.
- The top-level `cml --help` output shows the option entry as `--driver-token, --token  CI driver personal/project access token (PAT)`.


- If no driver token is provided, report an error containing the exact phrase `token not found`.
