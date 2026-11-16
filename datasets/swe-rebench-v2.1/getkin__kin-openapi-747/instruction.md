Additional properties false not validated
### Reproduction

```go
func TestAdditionalProperties(t *testing.T)
	schema := &openapi3.Schema{
		AdditionalProperties: openapi3.AdditionalProperties{
			Has: openapi3.BoolPtr(false),
		},
	}

	value := map[string]interface{}{"foo": 42}

	err := schema.VisitJSON(value)

	require.Error(t, err) // fails. err is nil
}
```

### Expected

I'm expecting this to return an error as `"foo"` isn't defined in `properties` and is not allowed by `additionalProperties`.

### Actual

The above test returns `nil`.

### Additional contract requirements

- For the reproduced input, the error returned by `VisitJSON` must be a `*SchemaError` with `SchemaField` equal to `"properties"` and `Reason` equal to `property "foo" is unsupported`.
