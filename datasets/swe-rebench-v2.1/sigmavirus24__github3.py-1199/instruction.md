`Branch.sync_with_upstream` sends incomplete data
Hello, first of all thank you so much for this incredible library!

I tried to sync my repos default branches with upstream using `Branch.sync_with_upstream`, but it failed with `github3.exceptions.ForbiddenError: 403 Resource not accessible by personal access token`.

Comparing the data sent by github3.py with the curl example in the GH API docs, it seems like we are missing the content added by that command's `-d '{"branch":"main"}'`.

I'll submit a PR to fix this, but wanted to file this issue so you can mention it if another solution is deemed more appropriate.

Edited to add (from template that was only shown at new PR creation):


## Version Information

Python: 3.12. 7
pip: 24.2
github3.py: 4.0.1, also git at [3b31f12](https://github.com/devdanzin/github3.py/commit/3b31f12f6b74b44e6828cde9264cd2402c0bd782)
requests: 2.32.3
uritemplate: 4.1.1
python-dateutil: 2.9.0.post0

## Minimum Reproducible Example

```python
def sync_default_branches():
    user = github3.login(USER, token=AUTH_TOKEN)
    repositories: typing.Generator[github3.github.repo.ShortRepository] = user.repositories(
        number=5, sort="fullname"
    )

    for repo in repositories:
        full_repo: [github3.github.repo.Repository] = repo.refresh()
        default_branch: github3.github.repo.branch.Branch = full_repo.branch(full_repo.default_branch)
        print(f"Syncing branch {default_branch.name} in {full_repo.full_name}.")
        try:
            result = default_branch.sync_with_upstream()
            print(result)
            print("Done\n")
        except Exception as e:
            print(f"Failed to sync branch {default_branch.name}: {e}\n")
```

## Exception information

Syncing doesn't work, but it does if we send `'{"branch":"NAME_OF_BRANCH"}'` in the request.
