S3 list bucket and list all buckets response should have content-type application/xml instead of text/html
Currently a lot of responses incorrectly have content-type text/html.  Instead they should have application/xml when appropriate.

### Additional contract requirements

- The `head_bucket` response must have content-type `application/xml`.
- S3 responses whose representations are XML must use content-type `application/xml` rather than `text/html`.
