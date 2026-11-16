Support state_reason in IssuesService.Edit

I would like to be able to use the API to close an issue with a reason why like you can in the UI (https://github.blog/changelog/2022-05-19-the-new-github-issues-may-19th-update/ , https://github.blog/changelog/2022-03-10-the-new-github-issues-march-10th-update/ ). I looked at the Issues API documentation and couldn't find reference to these closing reasons (https://docs.github.com/en/rest/issues/issues#update-an-issue) but I contacted support and they stated:

> The API now supports closing issues with state reasons. I'd reach out to the docs team to help update this in the API documentation.
>
> Here is a sample query you can run:
>
> ```text
> curl -X PATCH -H "Accept: application/vnd.github.v3+json" -H "Authorization: token {TOKEN}" https://api.github.com/repos/{org_name}/{repo_name}/issues/{issue-id} -d '{"state":"closed","state_reason":"not_planned"}'
> ```
>
> `"state_reason"` can either be `completed` or `not_planned`.

### Additional contract requirements

- The issue edit request type exposes a public field `StateReason` of type `*string` that is sent as the `state_reason` JSON parameter when editing an issue.
- The issue edit request type exposes a public method `GetStateReason() string` that returns the value of `StateReason` when the request and the field are non-nil, and an empty string otherwise.
