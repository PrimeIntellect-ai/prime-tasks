Semaphore CI 2.0 uses different CI environment variables
The current Semaphore task supports only Semaphore's "classic" CI environment, whereas in 2.0 they changed up the environment variables:

https://docs.semaphoreci.com/article/12-environment-variables

`REVISION` -> `SEMAPHORE_GIT_SHA`
`BRANCH_NAME` -> `SEMAPHORE_GIT_BRANCH `
`SEMAPHORE_BUILD_NUMBER` -> `SEMAPHORE_JOB_ID `

I'm not sure if `PULL_REQUEST_NUMBER` hash changed or not, though—the documentation doesn't mention it at all.

### Additional contract requirements

- Use `SEMAPHORE_GIT_PR_NUMBER` for the pull-request number, and emit its value as `service_pull_request` in the generated JSON.
- Use `SEMAPHORE_GIT_BRANCH` (without a trailing space) instead of `BRANCH_NAME` for the branch, preserving its existing destination at `git.branch` in the generated JSON.
- Use `SEMAPHORE_JOB_ID` (without a trailing space) instead of `SEMAPHORE_BUILD_NUMBER` for the service number, preserving its existing destination at `service_number` in the generated JSON.
