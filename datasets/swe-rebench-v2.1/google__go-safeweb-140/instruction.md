Proposal: merge `ClientError` and `ServerError`
I think w.Error(Status, optionalResponse) could be enough, the response writer has enough information to decide what to do when given a status that is >400.
