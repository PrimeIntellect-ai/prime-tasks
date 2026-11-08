Encode payloads deterministically
### Is your feature request related to a problem? Please describe.

Instead of mocking complex use-cases, we want to speed up our test pipeline by using https://github.com/google/go-replayers through using a custom `*http.Client`. The problem is now that the payloads are not deterministic with the custom form encoder included in this SDK. Specifically map types, as used for metadata, are not encoded deterministic and therefore mess with the replayer:

```
metadata[interval]=monthly&metadata[plan]=Essentials%400&customer=cus_NKH10bl....
metadata[plan]=Essentials%400&metadata[interval]=monthly&customer=cus_NKH10bl....
```

### Describe the solution you'd like

The payload should be encoded deterministically. This could either be achieved by

[HIDDEN]

### Describe alternatives you've considered

[HIDDEN]

### Additional context

_No response_

### Additional contract requirements

- When `Strict` is false, `AppendTo` must ignore map entries with non-string keys without panicking.
