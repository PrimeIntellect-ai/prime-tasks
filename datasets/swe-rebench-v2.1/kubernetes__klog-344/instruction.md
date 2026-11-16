logr.Marshaler: does not handle non-string results
/kind bug

**What steps did you take and what happened:**

I wrote a MarshalLog implementation which returns a slice. klog called the function, but then logged the original value instead of the one returned by MarshaLog.

**What did you expect to happen:**

https://github.com/kubernetes/klog/blob/0990e81f1a8f011181187da59ef32356bb836330/internal/serialize/keyvalues.go#L148 [HIDDEN]

### Additional contract requirements

- When klog processes a `logr.Marshaler`, it should log the value returned by `MarshalLog`, rather than the original value, including when the returned value is non-string.
