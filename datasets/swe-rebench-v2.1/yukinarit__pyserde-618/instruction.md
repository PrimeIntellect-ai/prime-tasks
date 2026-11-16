pyserde unable to serialize a UUID inside of a dict[str, Any] in an object
Hi, the following serialization works in pyserde 0.14.1, but breaks in pyserde 0.14.2 (and later, up to 0.22.2)

```python
from uuid import UUID

@serde
@dataclass
class A:
    tags: dict[str, Any]

a = A(tags={'id': UUID('05b69d9a-3783-46ea-a811-35fa4b72ddac')})

to_dict(a)  # Works on 14.1, breaks on 14.2 (up to v0.22.2)
```

Here is the traceback:
```python
---------------------------------------------------------------------------
SerdeError                                Traceback (most recent call last)
Cell In[35], line 1
----> 1 to_dict(a)

File ~/Library/Caches/pypoetry/virtualenvs/test-env/lib/python3.10/site-packages/serde/se.py:461, in to_dict(o, c, reuse_instances, convert_sets)
    436 def to_dict(
    437     o: Any,
    438     c: Optional[Type[Any]] = None,
    439     reuse_instances: Optional[bool] = None,
    440     convert_sets: Optional[bool] = None,
    441 ) -> Dict[Any, Any]:
    442     """
    443     Serialize object into dictionary.
    444
   (...)
    459     [{'i': 10, 's': 'foo', 'f': 100.0, 'b': True}, {'i': 20, 's': 'foo', 'f': 100.0, 'b': True}]
    460     """
--> 461     return to_obj(  # type: ignore
    462         o, named=True, c=c, reuse_instances=reuse_instances, convert_sets=convert_sets
    463     )

File ~/Library/Caches/pypoetry/virtualenvs/test-env/lib/python3.10/site-packages/serde/se.py:389, in to_obj(o, named, reuse_instances, convert_sets, c)
    386     return o
    388 except Exception as e:
--> 389     raise SerdeError(e) from None

SerdeError: maximum recursion depth exceeded while calling a Python object
```

### Additional contract requirements

- When a `dict[str, Any]` field contains a `datetime`, `to_dict` must serialize it as the string returned by `datetime.isoformat()`; UUID values must be serialized as strings.
