How to properly document a file response?
Hi.

I wonder if there is a proper way to document the output of an endpoint that returns a file as a response. I haven't found anything in the documentation. If a method exists, it would be good to include an example.

Thank you
KR
Eduardo

### Additional contract requirements

`APIFlask.output` must accept a `content_type` argument for the response media type. It defaults to `application/json`; when a different media type is supplied, that media type is represented in the endpoint's generated OpenAPI response documentation. For example, a file response can be documented with `@app.output(FileSchema, content_type='application/pdf')`.
