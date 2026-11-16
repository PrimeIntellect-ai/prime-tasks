Create embeddings
Given uri:
https://api.openai.com/v1/embeddings

Create sttp POST endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/embeddings

### Additional contract requirements

- Add a public case class `EmbeddingResponse(object: String, data: Seq[EmbeddingData], model: String, usage: Usage)` in `sttp.openai.requests.embeddings.EmbeddingsResponseBody`.
- Add a public case class `EmbeddingData(object: String, index: Int, embedding: Seq[Double])` in `sttp.openai.requests.embeddings.EmbeddingsResponseBody`.
- Add a public case class `Usage(promptTokens: Int, totalTokens: Int)` in `sttp.openai.requests.embeddings.EmbeddingsResponseBody`.
- Add a public method `createEmbeddings(embeddingsBody: EmbeddingsBody)` on `sttp.openai.OpenAi` that returns a request using the HTTP POST method and targeting `https://api.openai.com/v1/embeddings`.
- The request returned by `createEmbeddings` includes the supplied `EmbeddingsBody` as its request body.
- Successful JSON responses from the embeddings endpoint are decoded as `EmbeddingResponse` using the project's JSON conventions.
- Add a public case class `EmbeddingsBody(model: String, input: EmbeddingsInput)` in `sttp.openai.requests.embeddings.EmbeddingsRequestBody`.
- Add a public `EmbeddingsInput` type in `sttp.openai.requests.embeddings.EmbeddingsRequestBody`, with a public case class `SingleInput(value: String)` nested in `EmbeddingsInput`.
