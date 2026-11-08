Gates should output `X` (never `Z`) when inputs are invalid
### Describe the bug

Some gates (e.g. the `Mux`) will potentially output a `Z` if the input (e.g. the control) is a `Z` instead of outputting an `X`.  We should fix the `Mux` and also search for any other gates or built-in modules that may be outputting a `Z` instead of an `X` when inputs are invalid.

### To Reproduce

Set the control on `Mux` to `Z`, and observe output value.

### Expected behavior

Output is `X`

### Actual behavior

Output is `Z`

### Additional: Dart SDK info

_No response_

### Additional: pubspec.yaml

_No response_

### Additional: Context

_No response_
