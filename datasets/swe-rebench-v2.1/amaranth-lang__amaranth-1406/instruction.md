Views with an array layout should have `len()` applicable to them
Currently this isn't possible:

```python
width = 8
sig = Signal(data.ArrayLayout(1, width))
len(sig) # => TypeError: object of type 'View' has no len()
```
