Pass -ignoretests to errcheck when "tests" flag is false
`  -t, --tests               Include test files for linters that support this option`
And yet - without it being set, errcheck checks tests files while it supports a flag to skip them.
