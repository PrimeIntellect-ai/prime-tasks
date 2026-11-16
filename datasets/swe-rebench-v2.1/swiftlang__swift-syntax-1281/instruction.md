Generic where clause defaults to same-type requirement if no `==`, `:`, etc is given
### Issue Kind

Bad Diagnostic Produced

### Source Code

```swift
@differentiable(reverse wrt,where T
func podcastPlaybackSpeed() {
}
```


### Description

This produces the following diagnostics:

```swift
     DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected ':' in '@differentiable' argument"),
     DiagnosticSpec(locationMarker: "DIAG_1", message: "Expected parameters of '@differentiable' argument"),
     DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected '=' in same type requirement"),
     DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected right-hand type of same type requirement"),
     DiagnosticSpec(locationMarker: "DIAG_2", message: "Expected ')' to end attribute"),
```

Clearly we shouldn’t be complain gin about a same-type requirement but tell the user that any kind of requirement is missing after `T`.
