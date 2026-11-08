Create moderation
Given uri:
`https://api.openai.com/v1/moderations`

Create sttp POST endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/moderations

### Additional contract requirements

- Add a public method `createModeration(moderationsBody: ModerationsBody)` on `sttp.openai.OpenAi` that returns a request performing an HTTP POST to `https://api.openai.com/v1/moderations`.
- Add a public case class `ModerationsBody(input: String)` in `sttp.openai.requests.moderations.ModerationsRequestBody`.
- Provide `ModerationData(id: String, model: String, results: Seq[Result])` in `sttp.openai.requests.moderations.ModerationsResponseData`.
- Provide `Result(flagged: Boolean, categories: Categories, categoryScores: CategoryScores)` in `sttp.openai.requests.moderations.ModerationsResponseData`.
- Provide `Categories(sexual: Boolean, hate: Boolean, violence: Boolean, self-harm: Boolean, sexual/minors: Boolean, hate/threatening: Boolean, violence/graphic: Boolean)` in `sttp.openai.requests.moderations.ModerationsResponseData`.
- Provide `CategoryScores(sexual: Double, hate: Double, violence: Double, self-harm: Double, sexual/minors: Double, hate/threatening: Double, violence/graphic: Double)` in `sttp.openai.requests.moderations.ModerationsResponseData`.
