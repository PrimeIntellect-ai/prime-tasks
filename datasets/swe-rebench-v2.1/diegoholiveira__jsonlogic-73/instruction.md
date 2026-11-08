filter body returns error when used with array-form var
Using the full `{"var": [...]}` syntax instead of the syntax sugar `{"var": "..."}` causes an error when present in a `filter` body. As an example, the following rule (adapted from the test suite) will fail:

```json
	{
		"filter": [
			{"var": ["people"]},
			{"==": [
				{"var": [".age"]},
				{"min": {"map": [
					{"var": ["people"]},
					{"var": [".age"]}
				]}}
			]}
		]
	}
```
with the data:
```json
	{
		"people": [
			{"age":18, "name":"John"},
			{"age":20, "name":"Luke"},
			{"age":18, "name":"Mark"}
		]
	}
```

I believe the cause is this line: https://github.com/diegoholiveira/jsonlogic/blob/master/vars.go#L15
