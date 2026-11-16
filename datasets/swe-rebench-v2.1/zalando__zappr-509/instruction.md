Error when setting up branch protection
When trying to set up branch protection in repositories that Zappr is newly enabled for, we get an error from the GitHub API:

```
zappr:github:error 2017-06-08T10:02:38Z 422 PUT /repos/XXX/YYY/branches/master/protection { message: 'Invalid request.\n\n"enforce_admins" wasn\'t supplied.',
(truncated)
```

### Additional contract requirements

- When setting up branch protection, include `enforce_admins: true` in the GitHub API request payload.
