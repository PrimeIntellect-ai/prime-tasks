Bug when using a percent (%) symbol query parameter value
When a percent (%) symbol is used as part of the query parameter it will blow up [HIDDEN].
This was tested on:
- Chrome 68.0.3440.84 on Mac
- Microsoft Edge 80.0.361.33 on Mac
- Safari 13.0.2 (15608.2.30.1.1)

The current workaround is to encode the URI before sending to setQueryParams

### Additional contract requirements

Query parameter values containing a literal percent sign must be usable without caller-side pre-encoding, must not cause decoding to fail, and must be returned with the literal value preserved.
