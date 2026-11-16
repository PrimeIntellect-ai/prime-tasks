A false positive for C416
Hi,

I saw some fixes were committed for C416 false positives before, and I believe I've found a new one.

I was working on some code, which converts a list of 2-element sequences to a list of 2-tuples:

```python
from typing import List, Tuple

a_list_of_2lists: List[List[int]] = [[i, i + 1] for i in range(10)]

a_list_of_2tuples: List[Tuple[int, int]] = [(a, b) for a, b in a_list_of_2lists]
```

Incidentally, the code passes if I create a 3-tuple instead:

```python
a_list_of_3tuples: List[Tuple[int, int, str]] = [(a, b, 'foobar') for a, b in a_list_of_2lists]
```

Then I had this idea:
```
a_list_of_2tuples: List[Tuple[int, int]] = [tuple((a, b)) for a, b in a_list_of_2lists]
```
but that gave me a C409

Cheers
