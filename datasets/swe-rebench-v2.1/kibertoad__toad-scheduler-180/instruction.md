How can I retrieve the TaskId or JobId in the handler?
I'd like to know what task or job is being executed in the handler.  Is that possible?

### Additional contract requirements

- A `Task` handler is invoked with the task's id as its first argument: `handler(taskId)`.
- An `AsyncTask` handler is invoked with the task's id as its first argument and, when the task is executed as part of a job, the job's id as its second argument: `handler(taskId, jobId)`.
- `SimpleIntervalJob` accepts an options object with an optional `id`; when provided, that id is passed to the task handler as the job id.
