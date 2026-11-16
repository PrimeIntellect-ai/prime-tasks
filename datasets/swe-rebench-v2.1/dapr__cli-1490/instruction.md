`max-body-size` and `read-buffer-size` do not accept units
## Expected Behavior

<!-- Briefly describe what you expect to happen -->
I should be able to define the arguments `max-body-size` and `read-buffer-size` with units, e.g. "4Mi" as per docs.
https://v1-15.docs.dapr.io/reference/arguments-annotations-overview/

## Actual Behavior

<!-- Briefly describe what is actually happening -->
At the moment, the flag is being parsed as an int rather than a string before invoking the runtime.

## Steps to Reproduce the Problem

<!-- How can a maintainer reproduce this issue (be detailed) -->
```
dapr run --app-id custom-grpc-client \
		 -d ./config \
		 --max-body-size 4Mi \
		 --log-level debug \
		 go run ./custom-grpc-client/main.go
```

## Release Note

<!-- How should the fix for this issue be communicated in our release notes? It can be populated later. -->
<!-- Keep it as a single line. Examples: -->

<!-- RELEASE NOTE: **ADD** New feature in Dapr. -->
<!-- RELEASE NOTE: **FIX** Bug in runtime. -->
<!-- RELEASE NOTE: **UPDATE** Runtime dependency. -->

RELEASE NOTE: **FIX** Allow `max-body-size` and `read-buffer-size` to be defined with units

### Additional contract requirements

- The default values for `max-body-size` and `read-buffer-size` must be `4Mi` and `4Ki`, respectively.
- When `max-body-size` is set to `4000000`, the runtime argument must be `4M`.
- For unit-bearing values, preserve the supplied spelling in runtime arguments: `max-body-size` values `4Mi` and `5M` must be emitted as `4Mi` and `5M`, respectively, and `read-buffer-size` value `4Ki` must be emitted as `4Ki`.
