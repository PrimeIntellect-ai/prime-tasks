🐛 [Bug]: EnvVar middleware parsing error
### Bug Description

```go
func TestEnvVarHandlerSpecialValue(t *testing.T) {
	os.Setenv("testEnvKey", "testBase64:TQ==")
	defer os.Unsetenv("testEnvKey")

	app := fiber.New()
	app.Use("/envvars", New())

	req, _ := http.NewRequest("GET", "http://localhost/envvars", nil)
	resp, err := app.Test(req)
	utils.AssertEqual(t, nil, err)

	respBody, err := ioutil.ReadAll(resp.Body)
	utils.AssertEqual(t, nil, err)

	var envVars EnvVar
	utils.AssertEqual(t, nil, json.Unmarshal(respBody, &envVars))
	val := envVars.Vars["testEnvKey"]
	utils.AssertEqual(t, "testBase64:TQ==", val)
}
```

```go
=== RUN   TestEnvVarHandlerSpecialValue
    envvar_test.go:124:
        Test:       TestEnvVarHandlerSpecialValue
        Trace:      envvar_test.go:124
        Expect:     testBase64:TQ==     (string)
        Result:     testBase64:TQ       (string)
--- FAIL: TestEnvVarHandlerSpecialValue (0.00s)

FAIL
```


### How to Reproduce

Run the above test case.

### Expected Behavior

PASS

### Fiber Version

v2.37.0

### Code Snippet (optional)

_No response_

### Checklist:

- [X] I agree to follow Fiber's [Code of Conduct](https://github.com/gofiber/fiber/blob/master/.github/CODE_OF_CONDUCT.md).
- [X] I have checked for existing issues that describe my problem prior to opening this one.
- [X] I understand that improperly formatted bug reports may be closed without explanation.
