Recover status code after request
Hi!

I am using ``gidgethub`` to create a bot within a GitHub App. I am struggling when checking whether a user is member of a certain organization, see [GitHub documentation](https://docs.github.com/en/rest/orgs/members#check-organization-membership-for-a-user) for this call.

From what I understood, ``gh.getitem`` only returns the body of the request. However, the call mentioned above only returns a status code as a response (either 204, 302 or 404). Thus, I am not sure how to recover this status code after using ``await gh.getitem(url, oauth_token=oauth_token)``.

Please, let me know if I am misunderstanding something. Thanks!

### Additional contract requirements

Expose a public `getstatus` operation on `GitHubAPI` that makes a GET request and returns the integer HTTP status code even when the response body is not useful. It must report the status-only outcomes described above (204, 302, and 404). When an HTTP error response is surfaced as an HTTP exception, return that response's status code.
