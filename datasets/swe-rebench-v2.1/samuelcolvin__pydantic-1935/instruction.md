Accept deque as sequence-like input data type
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this feature/change is needed
* [x] After submitting this, I commit to one of:
    * Look through open issues and helped at least one other person
    * Hit the "watch" button on this repo to receive notifications and I commit to help at least 2 people that ask questions in the future
    * Implement a Pull Request for a confirmed bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Feature Request

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.6.1
            pydantic compiled: True
                 install path: /home/quan/.local/lib/python3.8/site-packages/pydantic
               python version: 3.8.2 (default, Jul 16 2020, 14:00:26)  [GCC 9.3.0]
                     platform: Linux-5.4.0-47-generic-x86_64-with-glibc2.29
     optional deps. installed: []

```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your feature hasn't been asked for before, or already implemented. -->

Code snippet:

```py
from collections import deque
from typing import List
from pydantic import BaseModel


class Ticket(BaseModel):
    numbers: List[int] = []


Ticket.parse_obj({'numbers': deque((1, 3, 5))})
```

Got error:

```py
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "pydantic/main.py", line 455, in pydantic.main.BaseModel.parse_obj
  File "pydantic/main.py", line 346, in pydantic.main.BaseModel.__init__
pydantic.error_wrappers.ValidationError: 1 validation error for Ticket
numbers
  value is not a valid list (type=type_error.list)

1 validation error for Ticket
numbers
  value is not a valid list (type=type_error.list)

```

I expect to get:

```py
Ticket(numbers=[1, 3, 5])
```

### Additional contract requirements

- A field annotated with `typing.Deque[T]` is a supported field type, as is a field annotated with the bare `collections.deque` type.
- Such a field accepts a `collections.deque`, `list`, `tuple`, `set`, `frozenset`, or generator as input, validates each item against `T`, and produces a `collections.deque` of the validated items.
- A `typing.Sequence[T]` field accepts a `collections.deque` as input and produces a `collections.deque` of the validated items.
- A `collections.deque` value is serialized to JSON as a JSON array; for example a `Deque[int]` field holding `deque((1, 2, 3))` serializes to `[1, 2, 3]`.
- An invalid value for a `deque` field raises a validation error.
