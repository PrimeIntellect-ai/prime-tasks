`TypeError` when drawing from a strategy that produces `dataclasses` with a `defaultdict` attribute
Since Hypothesis `6.92.0`, some [tests](https://github.com/schemathesis/schemathesis/actions/runs/7162876716/job/19500510033) in Schematesis started to fail with a traceback like this:

```python-traceback
@given(data=st.data())
  >   @settings(deadline=None)

  test/test_hypothesis.py:450:
  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
  test/test_hypothesis.py:476: in test_date_format
      case = data.draw(strategy)
  .tox/py38/lib/python3.8/site-packages/hypothesis/strategies/_internal/core.py:2106: in draw
      self.conjecture_data._observability_args[desc] = to_jsonable(result)
  [HIDDEN]
  /opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/dataclasses.py:10[73](https://github.com/schemathesis/schemathesis/actions/runs/7162876716/job/19500510033#step:6:74): in asdict
      return _asdict_inner(obj, dict_factory)
  /opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/dataclasses.py:10[80](https://github.com/schemathesis/schemathesis/actions/runs/7162876716/job/19500510033#step:6:81): in _asdict_inner
      value = _asdict_inner(getattr(obj, f.name), dict_factory)
  /opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/dataclasses.py:1080: in _asdict_inner
      value = _asdict_inner(getattr(obj, f.name), dict_factory)
  /opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/dataclasses.py:1080: in _asdict_inner
      value = _asdict_inner(getattr(obj, f.name), dict_factory)
  /opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/dataclasses.py:1080: in _asdict_inner
      value = _asdict_inner(getattr(obj, f.name), dict_factory)
  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

  obj = defaultdict(<class 'list'>, {}), dict_factory = <class 'dict'>

      def _asdict_inner(obj, dict_factory):
          if _is_dataclass_instance(obj):
              result = []
              for f in fields(obj):
                  value = _asdict_inner(getattr(obj, f.name), dict_factory)
                  result.append((f.name, value))
              return dict_factory(result)
          elif isinstance(obj, tuple) and hasattr(obj, '_fields'):
              # obj is a namedtuple.  Recurse into it, but the returned
              # object is another namedtuple of the same type.  This is
              # similar to how other list- or tuple-derived classes are
              # treated (see below), but we just need to create them
              # differently because a namedtuple's __init__ needs to be
              # called differently (see bpo-34363).

              # I'm not using namedtuple's _asdict()
              # method, because:
              # - it does not recurse in to the namedtuple fields and
              #   convert them to dicts (using dict_factory).
              # - I don't actually want to return a dict here.  The main
              #   use case here is json.dumps, and it handles converting
              #   namedtuples to lists.  Admittedly we're losing some
              #   information here when we produce a json list instead of a
              #   dict.  Note that if we returned dicts here instead of
              #   namedtuples, we could no longer call asdict() on a data
              #   structure where a namedtuple was used as a dict key.

              return type(obj)(*[_asdict_inner(v, dict_factory) for v in obj])
          elif isinstance(obj, (list, tuple)):
              # Assume we can create an object of this type by passing in a
              # generator (which is not true for namedtuples, handled
              # above).
              return type(obj)(_asdict_inner(v, dict_factory) for v in obj)
          elif isinstance(obj, dict):
  >           return type(obj)((_asdict_inner(k, dict_factory),
                                _asdict_inner(v, dict_factory))
                               for k, v in obj.items())
  E           TypeError: first argument must be callable or None
  E           Falsifying example: test_date_format(
  E               data=data(...),
  E           )
```

I am not sure if it is an issue on the Python or Hypothesis side, but it could be reproduced with the following snippet (running under `pytest`):


```python
from collections import defaultdict
from dataclasses import dataclass, field
from hypothesis import strategies as st, given


@dataclass
class T:
    key: defaultdict = field(default_factory=lambda: defaultdict(list))


@given(st.data())
def test_t(data):
    data.draw(st.builds(T))
```

Alternatively, I can try to work around this on the Schemathesis side. Let me know what you think! :)

### Additional contract requirements

- Drawing from a strategy that produces a dataclass with a `defaultdict` attribute must not raise the reported `TypeError`.
