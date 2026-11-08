Retrieve fine-tune
Given uri:
`https://api.openai.com/v1/fine-tunes/{fine_tune_id}`

Create sttp GET endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/fine-tunes/retrieve

### Additional contract requirements

Expose the retrieval operation as a public client method named `retrieveFineTune`. The method must request the fine-tune identified by its argument and return its decoded details and lifecycle events. Adding retrieval must not change the return contract of `createFineTune`: a successful call still yields the fine-tune details and lifecycle events decoded from the create response, and its result is still an sttp response whose body is either an error or those decoded values.
