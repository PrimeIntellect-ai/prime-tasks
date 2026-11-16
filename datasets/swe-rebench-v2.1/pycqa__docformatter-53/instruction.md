Remove the empty line between function definiton and docstring
If there is a blank line between function definition and the docstring, it should be removed:
```python
def my_func():

"""Summary of my function"""
```

should be modified to:

```python
def my_func():
"""Summary of my function"""
```
