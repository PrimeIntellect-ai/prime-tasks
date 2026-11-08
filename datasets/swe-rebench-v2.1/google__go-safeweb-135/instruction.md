Implement accessor methods for getting a file passed in a multipart request
A POST, PATCH or PUT request with the header `Content-Type:multipart/form-data` allows users to send files as part of the request. This is currently not implemented in  the `safehttp.MultipartForm` type. We need to investigate the behaviour of the current API, provided by `net/http`, and provide accessor methods for form files in the `safehttp` API

### Additional contract requirements

- Add a public method `File(param string) []*multipart.FileHeader` on the `safehttp.MultipartForm` type in the `safehttp` package. It returns the file parts associated with the multipart form field named `param`, or nil if the field is absent. Each returned `*multipart.FileHeader` can be opened to read its contents.
- Add a public method `RemoveFiles()` on the `safehttp.MultipartForm` type in the `safehttp` package. It removes any temporary files associated with the form.
