Allow payloads with no documents
To improve the usage of the API, we want to allow payloads with 0 documents when adding/updating documents to an index.

More details in the spec: https://github.com/meilisearch/specifications/pull/98

This concerns two routes
- `POST /indexes/:uid/documents`
- `PUT /indexes/:uid/documents`

An empty payload still returns the following error
`400 Bad Request - **missing_payload** error code.`

🔥 We must add tests 🔥

### Additional contract requirements

- For a `[]` payload, both routes must return HTTP status `202`.
- If the request has no body, both routes must continue to return HTTP `400` with the `missing_payload` error code. This is distinct from a present `[]` payload.
