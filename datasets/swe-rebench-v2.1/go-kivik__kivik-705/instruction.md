Unexport couchdb.BulkGetError

### Additional contract requirements

- For a bulk-get row error caused by an empty document ID, its error message must be `illegal_docid: Document id must not be empty`; for a missing document, it must be `not_found: missing`.
