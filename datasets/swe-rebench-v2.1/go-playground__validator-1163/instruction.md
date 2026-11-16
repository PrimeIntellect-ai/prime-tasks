Required behaviour changed for time.Time
- [X] I have looked at the documentation [here](https://pkg.go.dev/github.com/go-playground/validator/v10#section-documentation) first?
- [X] I have looked at the examples provided that may showcase my question [here](/_examples)?

### Package version eg. v9, v10:

v10.15.2

### Issue, Question or Enhancement:

A zero `time.Time` passes the `required` validation in v10.15.2 but not in v10.15.1. Adding in `WithRequiredStructEnabled` to the `New()` func does enable the test to pass but I'm not sure if I should make this code change in our codebase; should the default behaviour have changed between these minor releases?

I've provided a sample test that passes in v10.15.1 but fails in v10.15.2.

### Code sample, to showcase or reproduce:

```go
func TestTimeRequired(t *testing.T) {
	validate := New()
	validate.RegisterTagNameFunc(func(fld reflect.StructField) string {
		name := strings.SplitN(fld.Tag.Get("json"), ",", 2)[0]

		if name == "-" {
			return ""
		}

		return name
	})

	type TestTime struct {
		Time time.Time `validate:"required"`
	}

	var testTime TestTime

	err := validate.Struct(&testTime)
	NotEqual(t, err, nil)
	AssertError(t, err.(ValidationErrors), "TestTime.Time", "TestTime.Time", "Time", "Time", "required")
}
```
