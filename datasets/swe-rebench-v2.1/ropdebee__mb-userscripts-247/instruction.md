Improve error message on unsupported file formats
If we could, we should add the received MIME type in the error message (perhaps extract it from the fetch response header). We should also raise a specific error if we get text or HTML instead of images, since the user may have accidentally pasted the wrong link.

### Additional contract requirements

- When the response has `Content-Type: text/html; charset=utf-8`, the error message must include `Expected to receive an image, but received text. Perhaps this provider is not supported yet?`. When the response has `Content-Type: application/json` and the requested filename is `test.jpg`, the error message must include `Expected "test.jpg" to be an image, but received application/json.` When the response has no content-type header and the requested filename is `test.jpg`, the error message must include `Expected "test.jpg" to be an image, but received unknown file type.`
