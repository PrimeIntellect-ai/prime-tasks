Support `NotRequired` in `TypedDict` when `__future__.annotations` is enabled
### Description

[PEP 655](https://peps.python.org/pep-0655/) adds support for `NotRequired` and `Required`. Currently it seems `msgspec` doesn't support it, but it does support `total=False` when defining a `TypedDict`. Is this something that can be supported?

I actually encountered this when I was trying to create a typed dictionary for specifying the values that can be updated in a specific table in Postgres. That is, whichever values are provided would be updated. Initially I had something like this:

```python

class UpdateRequest(TypedDict):

    id: str
    some_value: NotRequired[int]
    another_value: NotRequired[str]
    ...
```
This is what the body of the request from the client was going to be. I refactored this to make it work with msgpec by doing the following:

```python

class UpdateEntity(TypedDict, total=False):

    some_value: int
    another_value: str
    ...

class UpdateRequest(TypedDict):

     id: str
     update_details: UpdateEntity
```
