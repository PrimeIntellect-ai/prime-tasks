ochttp public traceparent/tracestate marshal/unmarshal
**NB:** Before opening a feature request against this repo, consider whether the feature should/could be implemented in OpenCensus libraries in other languages. If so, please [open an issue on opencensus-specs](https://github.com/census-instrumentation/opencensus-specs/issues/new) first.



**Is your feature request related to a problem? Please describe.**
I wish to read and write traceparent/tracestate, encoded using [trace context](https://w3c.github.io/trace-context/), without passing an `http.Request`

**Describe the solution you'd like**
Two new methods should be added to [`HttpFormat`](https://github.com/census-instrumentation/opencensus-go/blob/master/plugin/ochttp/propagation/tracecontext/propagation.go#L46) or as public functions:

```
SpanContextFromHeaders(traceparent string, tracestate string) (sc trace.SpanContext, ok bool)
SpanContextToRequest(sc trace.SpanContext) (traceparent string, tracestate string)
```

**Describe alternatives you've considered**
AFAIK no alternatives are available in this library, except copy pasting that code in my own code.

### Additional contract requirements

The two new public APIs are methods on `HTTPFormat` in
`plugin/ochttp/propagation/tracecontext`:

```
func (f *HTTPFormat) SpanContextFromHeaders(tp string, ts string) (sc trace.SpanContext, ok bool)
func (f *HTTPFormat) SpanContextToHeaders(sc trace.SpanContext) (tp string, ts string)
```

The serialization method is named `SpanContextToHeaders` and returns the
`traceparent` and `tracestate` header values as two strings. The pre-existing
request-mutating method `SpanContextToRequest(sc trace.SpanContext, req *http.Request)`
keeps its signature and continues to write the two headers onto the request.
