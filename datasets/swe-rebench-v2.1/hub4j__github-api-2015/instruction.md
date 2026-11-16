401 when trying to extract GHUser#type
Hi, a code like this

```
new GitHubBuilder()
        .withJwtToken("token")
        .build()
        .getApp()
        .getInstallationById(githubInstallationId)
        .getAccount()
        .getType()
```

leads to 401:
```
Caused by: org.kohsuke.github.HttpException: {"message":"Bad credentials","documentation_url":"https://docs.github.com/rest"}
	at org.kohsuke.github.GitHubConnectorResponseErrorHandler$1.onError(GitHubConnectorResponseErrorHandler.java:62) ~[github-api-unbridged-1.318.jar:na]
```

There are a few issues here:
1. The field is already initialized as "Organization" after calling `getAccount()`, so populating here is not necessary, perhaps.
2. `installation.getAccount().getUrl()` returns `https://api.github.com/users/<ORGANIZATION_LOGIN>`, which perhaps is invalid, because it's an organization, not a user.
