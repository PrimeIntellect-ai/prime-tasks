Incorrect curl command for file upload (without multipart/form-data)
### Q&A (please complete the following information)

 - OS: macOS
 - Browser: Firefox
 - Version: 92
 - Method of installation: swagger-ui-react via npm
 - Swagger-UI version: 3.51.0
 - Swagger/OpenAPI version: OpenAPI 3.0

### Content & configuration

We use `swagger-ui-react` but this can also be reproduced using https://editor.swagger.io/.

Example Swagger/OpenAPI definition:
```yaml
openapi: 3.0.0
info:
  title: Test API
  version: '1.0'
servers:
  - url: 'http://localhost:3000'

paths:

  # Generated CURL request uses:
  #   -d '{}'
  # (This doesn't work; it could use something like --data-binary '@<file name>' instead.)
  /upload1:
    post:
      summary: Simple upload
      requestBody:
        required: true
        content:
          application/octet-stream:
            schema:
              type: string
              format: binary
      responses:
        '200':
          description: OK

  # Generated CURL request uses:
  #   -F 'fileName=@<file name>;type=<mime type>'
  # (This works fine.)
  /upload2:
    post:
      summary: Multipart upload
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                fileName:
                  type: string
                  format: binary
      responses:
        '200':
          description: OK
```

### Describe the bug you're encountering

In my OpenAPI 3.0 spec, I define a file upload endpoint by following the first example in [the relevant docs](https://swagger.io/docs/specification/describing-request-body/file-upload/) (_not_ using `multipart/form-data`). Calling that endpoint directly from Swagger UI works as expected (the UI offers to upload a file), but the generated CURL command doesn't show the expected option for the request body (it uses the option `-d '{}'` rather than something like `--data-binary '@<file name>'`).

### To reproduce...

Steps to reproduce the behavior:
1. Open the above Open API spec in Swagger UI or Swagger Editor
2. Open `/upload1`
3. Click on "Try it out"
4. The UI offers to chose a file to upload for the request body
5. Click execute; the request works as expected
6. The generated CURL request displayed shows the request body `-d '{}'`

### Expected behavior

Since the UI does offer to upload a file, I would expect the generated CURL command to also treat this as a binary file upload. I'd probably use the option `--data-binary '@<file name>'` (`--file-upload` would also work but only for `PUT` requests, not for `POST` requests).

### Additional context or thoughts

This would be consistent with what is already done for multi-part file uploads, where the generated CURL command uses the option `-F 'fileName=@<file name>;type=<mime type>'`.

I found a few existing issues regarding multipart file uploads (which were fixed and led to the behavior of using `-F 'fileName=@<file name>;type=<mime type>'`), but not for the case where multipart is not used; hopefully I didn't miss anything and this isn't a duplicate...
