Balanced accuracy does not work for binary case
There seems to be an issue with the balanced accuracy when the class labels are binary labels. I.e.,

```python
from mlxtend.evaluate import accuracy_score

a = [0, 0, 0, 0, 1, 1]
b = [0, 0, 1, 1, 1, 1]

accuracy_score(a, b)
0.6666666666666666

```
and

```python
accuracy_score(a, b, method='average')
0.6666666666666666
```

even though the second result should be 0.75
