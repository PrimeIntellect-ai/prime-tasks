We do not set allows_public_repositories for actions runner groups
We currently cannot set the `allows_public_repositories` variable wich is an entity of a runner group and controls weither public repos can use that group. If it is set to false, public repos, even if they are specifically in the selected repos list, will not be able to use the runners from this group.

The docs on this are:
https://docs.github.com/en/rest/reference/actions#create-a-self-hosted-runner-group-for-an-organization

However there is a documentation bug since we tried it out and one can actually pass this value to api in the request body and not only gets it as response. It will be set properly. This is not how it is documented in GitHub API Docs. Thus we raised an issue to change docs on this since we guess it is intended to be used in request body and just not properly documented.
https://github.com/github/docs/issues/8209

However we still miss the implementation in go-github.
So currently all Runner Groups created with this lib are  just for private repo since this flag is defaulted to false.

### Additional contract requirements

Both `CreateRunnerGroupRequest` and `UpdateRunnerGroupRequest` must expose the flag as a Go field named `AllowsPublicRepositories`. When supplied, each request must serialize its value as `allows_public_repositories` in the JSON request body. The update request must allow callers to change the flag on an existing runner group.
