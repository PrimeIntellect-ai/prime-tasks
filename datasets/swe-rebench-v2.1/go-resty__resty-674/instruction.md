parseResponseBody overrides original error code in case of unmarshalling error
If the client has an `Error` object for automatic unmarshalling for the request, and the JSON response cannot be unmarshalled, the current behavior is to override the HTTP response status with a marshalling error like `unexpected end of JSON input`.

Since we cannot lose this information, I suggest to change:
```
                        if res.Request.Error != nil {
                              [HIDDEN]
                        }

```
to:
```
                        if res.Request.Error != nil {
                              [HIDDEN]
                        }
```
This way [HIDDEN] but at least we can handle the server response status.

Maybe there's a better way to report the error, but I haven't found anyone ATM, please suggest an alternative if any.

### Additional contract requirements

- If automatic unmarshalling of an error response fails, preserve the server's HTTP status error rather than replacing it with the unmarshalling error.
