Add support for getting a workflow run attempt
I would like to add support for getting a workflow run by specifying the attempt number. From this doc:
https://docs.github.com/en/rest/reference/actions#get-a-workflow-run-attempt

I would like to ask about the naming convention for the method. I was considering either `GetWorkflowRunByAttempt` or `GetWorkflowRunByIDByAttempt`. Could someone please help me with the appropriate name?

This is my initial proposed method:
`GetWorkflowRunByAttempt(ctx context.Context, owner, repo string, runID int64, attemptNumber int) (*WorkflowRun, *Response, error)`

I started working on the code changes for this so this issue can be assigned to me.
Thank you!!

### Additional contract requirements

A caller can retrieve a single attempt of an existing GitHub Actions workflow run, selected by the run ID and a 1-based attempt number, and receive that attempt as a `WorkflowRun`.

The public API for this is:

- `ActionsService.GetWorkflowRunAttempt(ctx context.Context, owner, repo string, runID int64, attemptNumber int, opts *WorkflowRunAttemptOptions) (*WorkflowRun, *Response, error)`.
- `WorkflowRunAttemptOptions` with an `ExcludePullRequests *bool` field, which is sent as the endpoint's `exclude_pull_requests` query parameter when set.
- `WorkflowRunAttemptOptions.GetExcludePullRequests() bool`, which returns the option value, or `false` when the option or its field is unset.
