List fine-tune events
Given uri:
`https://api.openai.com/v1/fine-tunes/{fine_tune_id}/events`

Create sttp GET endpoint + tests

docs reference
https://platform.openai.com/docs/api-reference/fine-tunes/events

### Additional contract requirements

- Expose the operation as `OpenAi.getFineTuneEvents(fineTuneId: String)`, issuing a GET request to the fine-tune events endpoint given in the issue.
- Deserialize the response into the public `FineTuneEventsResponse` model, preserving the top-level `object` value and the event records in `data`. Each record must retain its `object`, `level`, `message`, and `createdAt` values.
