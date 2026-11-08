Allow overriding of global and system configuration
Git v2.32.0 introduced two new environment variables, `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM`, for overriding global and system configurations which is especially useful for executing `git` commands in a sanitized environment. Since Dulwich already supports `GIT_CONFIG_NOSYSTEM`, I think it would be great to also add these two environment variables.

See https://github.com/git/git/commit/4179b4897f2de28858acaebd6382c06c91532e98 for the original commit in the `git` project.
