Delete fine-tune model
Given uri:
`https://api.openai.com/v1/models/{model}`

Create sttp DELETE endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/fine-tunes/delete-model

### Additional contract requirements

- Add a public method `deleteFineTuneModel(model: String)` on `OpenAi` that returns a request performing an HTTP `DELETE` to `https://api.openai.com/v1/models/{model}`.
- Add a public case class `DeleteFineTuneModelResponse(id: String, object: String, deleted: Boolean)` in `sttp/openai/requests/finetunes/FineTunesResponseData.scala`, usable to deserialize the JSON payload returned by the delete-model endpoint.
