Delete file
Given uri:
`https://api.openai.com/v1/files/{file_id}`

Create sttp DELETE endpoint + tests

Docs reference
https://platform.openai.com/docs/api-reference/files/delete

### Additional contract requirements

Expose the deletion operation as `OpenAi.deleteFile(fileId: String)`. It must issue an HTTP DELETE request to `https://api.openai.com/v1/files/{file_id}`, replacing `{file_id}` with the supplied file ID.
