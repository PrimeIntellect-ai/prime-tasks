Update PipelineBase.load() to accept both a path and a file-like object
Currently, PipelineBase.load() accepts just a file path.  I have some scenarios in which I have a BytesIO object that I would like to pass into the function.

Proposed update:
1. Allow str or BytesIO as the argument
2. [HIDDEN]
3. If str, business as usual

### Additional contract requirements

- `PipelineBase.load()` must accept a `BytesIO` containing a serialized pipeline and return the deserialized pipeline.
