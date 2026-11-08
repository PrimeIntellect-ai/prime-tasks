length(dict) should return number of elements, not serialized length
`'{"a":"b","c":"d"}'.parseJson().length()` should evaluate to 2, not 17, as it currently does.

By contrast, `'["abc","def"]'.parseJson().length()` does correctly evaluate to 2


### Current Results

`'{"a":"b","c":"d"}'.parseJson().length()` evaluates to 17

### Expected Behavior

`'{"a":"b","c":"d"}'.parseJson().length()` evaluates to 2
