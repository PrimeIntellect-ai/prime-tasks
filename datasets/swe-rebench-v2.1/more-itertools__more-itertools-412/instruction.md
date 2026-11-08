spy: changing the result list changes the returned iterable
Changing the result list of `spy` also alters the iterable.

```python
In [1]: from more_itertools import spy

In [2]: it = range(10)

In [3]: head, it = spy(it, 3)

In [4]: head[1] = 'bad'

In [5]: list(it)
Out[5]: [0, 'bad', 2, 3, 4, 5, 6, 7, 8, 9]
```

 I think it is a case of implementation details leaking out.
