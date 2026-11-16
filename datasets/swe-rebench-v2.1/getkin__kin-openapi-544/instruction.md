Handling "default" in request body schema
(Apologies if I'm getting the nature of "default" completely wrong, but...)

I have an openapi3 request body schema which includes:

```json
          "group_by_time": {
            "default": true,
            "description": "Aggregate data over the provided time range, using the provided resolution. Default: true",
            "type": "boolean"
          },
```

For me, the ideal result of RequestBodyValidation would be a changed body that has `"group_by_time": true` if it is not otherwise set. I can think of many of reasons why this is a bad idea: req.Body -> JSON -> to new JSON -> to new Body is icky.

Also it doesn't appear that the json visitor would make the changes, as currently written.

So what is the correct or preferred way of achieving this? Should I simply be checking/setting the default in my code.

If there is a way to make this possible in the kin-openapi, I'm happy to work on the code if someone pushes me in the right direction.

### Additional contract requirements

- In package `openapi3filter`, the body-decoding helper has the signature
  `decodeBody(body io.Reader, header http.Header, schema *openapi3.SchemaRef, encFn EncodingFn) (mediaType string, value interface{}, err error)`.
  It returns the decoded value and an error when decoding fails.
- `decodeBody` returns the normalized media type that was matched (for example `application/json`), and an empty media type when the request's content type is unsupported.
