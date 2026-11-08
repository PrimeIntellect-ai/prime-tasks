Wrong Accept header for patch requests
`Content-Type` and `Accept` headers are set to the same value for every request (see [GenericHttpClient::request](https://github.com/mtarld/api-platform-ms-bundle/blob/1.x/src/HttpClient/GenericHttpClient.php#L51-L61)). However the response to a `PATCH` request is in the default format (like `application/ld+json`) and not `application/merge-patch+json`. Combined this leads to a 406 status code error when the default format is not `jsonapi`.

[HIDDEN] I could issue a PR if you don't mind.

### Additional contract requirements

- For `PATCH` requests, the `Accept` header must use the microservice's configured default MIME type.
