Need a function to remove status check contexts
I want to remove all the status checks that are added under my branch protection, to do so I tried using this `UPDATE` API call with the array of status checks as empty: https://docs.github.com/en/free-pro-team@latest/rest/reference/repos#update-status-check-protection
but I'm not able to achieve what I wanted.
Then I tried using this recent `DELETE` API to remove status checks,
https://docs.github.com/en/free-pro-team@latest/rest/reference/repos#remove-status-check-protection
It worked but there is no equivalent function in this go package. Can you add the same?

### Additional contract requirements

- Expose this functionality as `RepositoriesService.RemoveRequiredStatusChecks(ctx context.Context, owner, repo, branch string) (*Response, error)`.
