Allow the use of a list comprehension to initialise an array
### Describe the bug
A list comprehension must be saved to a variable in order to operate on the function, however currently it must be saved to a list variable. This is quite constraining. It would be nice to lift this restriction for NumPy arrays

### To Reproduce
Provide code to reproduce the behaviour:
```python
a = np.array([i*2 for i in range(5)])
```

### Error details
Provide the generated code, or the error message:
```
pyccel:
 |error [syntactic]: tmp.py [2,13]| The result of a list comprehension expression must be saved in a variable ([i * 2 for i in range(5)])
```

### Expected behavior
The error should still appear if the comprehension is not saved to a variable, but an exception should be added to allow the variable to be an array.

### Language
Syntactic error affects all languages

### Additional context
Needed by PyGyro
