$eval returns empty object if the context value is an empty array
When $eval is provided an empty array, it always returns empty object.

Example:
```
$eval("{ 'test': 1 }", [])
```

Output:
```json
{}
```

Expected Output:
```json
{
  "test": 1
}
```
