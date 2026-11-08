When test binary is used to run , rerun-fails option does not seem to work
Am using gotestsum as :
`~/go/src/gotest.tools/gotestsum/gotestsum  --format standard-verbose --rerun-fails --packages ./... --junitfile ./result.xml --rerun-fails-report something --raw-command -- go tool test2json -t -p global ./global.test -test.run TestPublicObjectUIDGetter -test.v  -test.parallel=1`

When the test fails, the rerun is not happening. Instead i see an error
`flag provided but not defined: -run`

Per https://github.com/gotestyourself/gotestsum/blob/master/rerunfails.go#L126, Seems like it is set to run only when `go test` is used.

[HIDDEN]

### Additional contract requirements

- When `--rerun-fails` is used with a raw test binary, rerun each failed test using a test-selection flag the binary accepts.
