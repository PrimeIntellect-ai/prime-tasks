Missing user exports endpoint?
Hi,

Are there plans to implement the `/api/v2/jobs/users-exports` endpoint? I was looking at `JobsManager.js` and could only see the import users endpoint implemented.

If not, I can probably help implement it as we have a need for it.

Thanks.

### Additional contract requirements

- Provide a public method `exportUsers(data, cb)` on `JobsManager` (module `src/management/JobsManager`). It creates a users export job by sending a `POST` request to `/api/v2/jobs/users-exports`, using `data` as the request payload.
- `data` is the export job payload object (for example `{ format: 'csv' }`).
- When a node-style callback `cb(err, result)` is supplied, the result is delivered through the callback and no Promise is returned. When `cb` is omitted, the method returns a Promise.
- The Promise resolves with the job object returned by the endpoint (for example an object carrying a `status` field).
- Errors from the HTTP request are propagated to the Promise rejection.
