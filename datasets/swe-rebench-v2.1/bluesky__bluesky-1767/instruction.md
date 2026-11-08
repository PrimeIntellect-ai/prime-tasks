Add bps.locate plan stub
We have a `Locate` message, but not a corresponding plan stub. Something like:
```python
@typing.overload
def locate(obj: Locatable, squeeze: Literal[True] = True) -> Location: ...
@typing.overload
def locate(*objs: Locatable, squeeze: bool = True) -> List[Location]: ...

[HIDDEN]
```
with the docstring from https://github.com/bluesky/bluesky/blob/main/src/bluesky/run_engine.py#L1959

### Additional contract requirements

- Add `bps.locate` as a plan stub that requests locating the supplied objects with the requested `squeeze` setting.
- With one object and `squeeze=True`, the plan returns a single `Location`. With `squeeze=False` or more than one object, it returns a list of `Location` objects.
