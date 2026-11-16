json encode bug
https://github.com/d5/tengo/blob/master/stdlib/json/json_test.go

try this test case `testJSONEncodeDecode(t, "1\u001C04")`

it reports `invalid character 'x' in string escape code`
