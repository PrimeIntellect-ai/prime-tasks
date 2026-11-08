[HIDDEN]
Per [the documentation](https://support.atlassian.com/bitbucket-cloud/docs/variables-and-secrets/):

> Default variable | Description
> -- | --
> BITBUCKET_REPO_FULL_NAME | The full name of the repository (everything that comes after http://bitbucket.org/).

https://github.com/codecov/uploader/blob/fe203d535ba08273b144daebaef5599975f80fdb/src/ci_providers/provider_bitbucket.js#L51-L59

### Additional contract requirements

- For Bitbucket builds, the resolved repository slug must reflect the full repository name supplied by `BITBUCKET_REPO_FULL_NAME`, including both the owner and repository components.
