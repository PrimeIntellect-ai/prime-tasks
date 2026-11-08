No Error Checking on `list_inputs` arg
### Description

When a user types `list_inputs(prom_name=True, return_format=dict)` instead of `list_inputs(prom_name=True, return_format='dict')` no error is thrown but the returned value is a list instead of a dictionary. An error should be thrown here.

### Example

```python
`prob.model.list_inputs(prom_name=True, return_format=dict)` on any openmdao model should trigger the error.
```


### OpenMDAO Version

3.27.1-dev

### Relevant environment information

NA

### Additional contract requirements

- Passing the string `'dict'` as `return_format` to `list_inputs` returns a dictionary.
