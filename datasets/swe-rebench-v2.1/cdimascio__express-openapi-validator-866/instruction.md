[HIDDEN] so files begin uploading before security check
**Describe the bug**

When `OpenApiValidator.middleware()` is configured to apply both upload and security middleware...
```js
OpenApiValidator.middleware({
  ...
  fileUploader: {
    storage: myDiskStorageEngine,
  },
  validateSecurity: {
    handlers: {
      securityCheck: mySecurityCheck,
    },
  },
})
```
... [HIDDEN] As a result, file uploads begin even for users that fail the security check.

The order of the middlewares is defined here:
https://github.com/cdimascio/express-openapi-validator/blob/bb8d6b80c4bc42be9213d03c46b5d3f0195d1040/src/openapi.validator.ts#L152-L179

**To Reproduce**
1. Configure `OpenApiValidator.middleware` with both a `fileUploader.storage` storage engine and a `validateSecurity` handler.
1. Attempt to upload a file using multipart/form-data with a request that does not satisfy `validateSecurity` handler.

**Actual behavior**
File upload will be processed. For example, if the multer storage engine is a disk storage engine, the file is written to disk.

**Expected behavior**
The security check should abort the request pipeline before the file upload is processed.

**Examples and context**
[HIDDEN] I am willing to create a PR for this change, but am unsure whether there's a reason for the current order (maybe the security check for some users depends on form data?). If so, perhaps the order could be configurable?

### Additional contract requirements

- When security validation rejects an upload request, the request must be stopped before any uploaded file is processed.
