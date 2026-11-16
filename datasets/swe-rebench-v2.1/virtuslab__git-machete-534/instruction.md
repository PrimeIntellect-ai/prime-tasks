Does `/pulls` endpoint for a public GitHub repository really require authentication?
As @mkondratek reported:

I've tried to use `create-pr` with that result:

```sh
mikko@mikko-MS-7C91:~/IdeaProjects/git-machete-intellij-plugin$ git machete github create-pr
Fetching origin...
Creating a PR from hook-executors-improvements to develop...Given endpoint: https://api.github.com/repos/VirtusLab/git-machete-intellij-plugin/pulls, not found in GitHub or you don't have the permission to access it (expired token?).
```

I have no token (generated and) set so that's the reason. After that - works.

_Originally posted by @mkondratek in https://github.com/VirtusLab/git-machete/issues/493#issuecomment-1113174706_

---

My addition: note that https://api.github.com/repos/VirtusLab/git-machete-intellij-plugin/pulls can be readily accessed from browser and returns legit results. Let's check why this error happens when accessing GitHub API from git-machete CLI. If this can't be circumvented (e.g. for private repos), let's at least improve the error message (since it doesn't even clearly state that the token might be missing, only mentions expiry) :thinking:

### Additional contract requirements

- When a GitHub API request to the `/pulls` endpoint fails with a 404 response, the error message must clearly state that a valid GitHub API token is required (rather than only mentioning an expired token). Specifically, the message must contain the text `A valid GitHub API token is required.`
