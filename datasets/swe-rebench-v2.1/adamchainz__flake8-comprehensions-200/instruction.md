C416 false positive with sequences as comprehension elements
The example below produces a C416 ("Unnecessary list comprehension - rewrite using list()"):
```py
input = [
    (1, 1),
    (1, 1),
    (1, 1),
]
output = [(x, y, 1) for x, y in input]
```
I suspect it is because both an input and output element is a tuple. I don't think it should happen since the shapes of the tuples differ.

It feels rather tricky to analyze the shape, so maybe in this case the check should be disabled.
