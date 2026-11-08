List fine-tunes
Given uri:
`https://api.openai.com/v1/fine-tunes`

Create sttp GET endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/fine-tunes/list

### Additional contract requirements

- Add a public method `getFineTunes` on `OpenAi` (package `sttp.openai`) that returns a GET request to `https://api.openai.com/v1/fine-tunes` and yields a `GetFineTunesResponse`.
- Add a public case class `CreateFineTuneResponse(fineTuneData: FineTuneData, events: Seq[Event])` in `sttp.openai.requests.finetunes.FineTunesResponseData`.
- Add a public case class `GetFineTunesResponse(`object`: String, data: Seq[FineTuneData])` in `sttp.openai.requests.finetunes.FineTunesResponseData`.
- Add a public case class `FineTuneData(`object`: String, id: String, hyperparams: Hyperparams, organizationId: String, model: String, trainingFiles: Seq[FileData], validationFiles: Seq[FileData], resultFiles: Seq[FileData], createdAt: Int, updatedAt: Int, status: String, fineTunedModel: Option[String])` in `sttp.openai.requests.finetunes.FineTunesResponseData`, where `FileData` is `sttp.openai.requests.files.FilesResponseData.FileData`.
- `Hyperparams` in `sttp.openai.requests.finetunes.FineTunesResponseData` must be `Hyperparams(nEpochs: Int, batchSize: Option[Int], promptLossWeight: Double, learningRateMultiplier: Option[Double])`.
