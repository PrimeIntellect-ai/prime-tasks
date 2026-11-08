Add `error` object to the update response in case of failure
Currently, we face an issue in the update response with `v0.24.0rc0` in case of failure, we have two `type` fields:

```json
{
        "status": "failed",
        "updateId": 1,
        "type": {
            "name": "DocumentsAddition"
        },
        "message": "Document doesn't have a `id` attribute: `{\"title\":\"Pride and Prejudice\",\"author\":\"Jane Austin\",\"genre\":\"romance\",\"price\":3.5}`.",
        "code": "missing_document_id",
        "type": "invalid_request",
        "link": "https://docs.meilisearch.com/errors#missing_document_id",
        "duration": 0.0,
        "enqueuedAt": "2021-11-04T13:07:54.577968Z",
        "processedAt": "2021-11-04T13:07:54.580385200Z"
 }
```

What we decide is to have an `error` field containing the information about the error

```json
{
        "status": "failed",
        "updateId": 1,
        "type": {
            "name": "DocumentsAddition"
        },
        "error": {
            "message": "Document doesn't have a `id` attribute: `{\"title\":\"Pride and Prejudice\",\"author\":\"Jane Austin\",\"genre\":\"romance\",\"price\":3.5}`.",
            "code": "missing_document_id",
            "type": "invalid_request",
            "link": "https://docs.meilisearch.com/errors#missing_document_id"
        },
        "duration": 0.0,
        "enqueuedAt": "2021-11-04T13:07:54.577968Z",
        "processedAt": "2021-11-04T13:07:54.580385200Z"
 }
```

⚠️ This only concerns the update response, not the response when we get a synchronous error.
