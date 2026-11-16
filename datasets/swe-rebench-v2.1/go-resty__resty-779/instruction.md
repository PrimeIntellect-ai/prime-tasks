Call to http.DetectContentType has trailing NUL bytes in buffer
In [`writeMultipartFormFile`](https://github.com/go-resty/resty/blob/v2/util.go#L211), the call to `http.DetectContentType` is passed a buffer with potentially trailing `0` bytes.  As a result, `text/plain` is never detected in such cases.

[HIDDEN]

```go
// Auto detect actual multipart content type
cbuf := make([]byte, 512)
[HIDDEN]
if err != nil && err != io.EOF {
  return err
}

partWriter, err := w.CreatePart(createMultipartHeader(fieldName, fileName, http.DetectContentType([HIDDEN])))
if err != nil {
  return err
}
```

### Additional contract requirements

- Multipart file content-type detection must use only the bytes actually read, so trailing NUL bytes do not prevent `text/plain` from being detected.
