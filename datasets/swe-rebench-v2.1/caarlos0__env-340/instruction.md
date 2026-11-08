Bug: fails to parse into fields with value
A regression was introduced in v7. When we pass a struct with non-nil pointer fields, `Parse` fails.

```go
func TestIssue(t *testing.T) {
	t.Run("Should parse with bool ptr set and env undefined", func(t *testing.T) {
		existingValue := true
		cfg := Config{
			BoolPtr: &existingValue,
		}

		isNoErr(t, Parse(&cfg))

		isEqual(t, &existingValue, cfg.BoolPtr)
	})

	t.Run("Should parse with bool ptr set and env defined", func(t *testing.T) {
		existingValue := true
		cfg := Config{
			BoolPtr: &existingValue,
		}

		newValue := false
		t.Setenv("BOOL", strconv.FormatBool(newValue))

		isNoErr(t, Parse(&cfg))

		isEqual(t, &newValue, cfg.BoolPtr)
	})
}
```

In 850c2d8 - this test passes.

In b135bbd and up to the current main - this test fails.

```
=== RUN   TestIssue/Should_parse_with_bool_ptr_set_and_env_undefined
    env_test.go:2199: unexpected error: env: expected a pointer to a Struct
```
