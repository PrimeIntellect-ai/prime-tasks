ApplyInterface does not support int number values
```
func main() {
	rule := map[string]interface{}{
		"==": []interface{}{
			map[string]interface{}{
				"var": "impact_levels",
			},
			1,
		},
	}

	data := map[string]interface{}{
		"impact_levels": 1,
	}

	output, err := jsonlogic.ApplyInterface(rule, data)
	if err != nil {
		fmt.Println(err)
		return
	}

	fmt.Println(output.(bool))
}
```
this returns an error, [HIDDEN]

### Additional contract requirements

- Integer support is required at the `ApplyInterface` API level: `ApplyInterface` must accept Go `int` values in both the rule and the data and treat them as numbers.
- For the supplied example, `ApplyInterface` must return a `bool` result (`true`) and a `nil` error.
- Comparing two integer values with `==` must return a `bool` (`true` when equal, `false` otherwise) without error.
