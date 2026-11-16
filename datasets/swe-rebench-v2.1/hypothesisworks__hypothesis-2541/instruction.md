`st.functions()` returning consistent (or pure) functions
Currently, `st.functions()` creates functions that are not-pure (in a sence that they don't return the same value for the same arguments).

My use-case is that I am testing monad laws (see https://github.com/dry-python/returns/issues/533 and https://github.com/dry-python/returns/pull/543 for more information). Here's one of the definitions:

```python
def associativity_law(
    mappable: MappableN[_FirstType, _SecondType, _ThirdType],
    first: Callable[[_FirstType], _NewType1],
    second: Callable[[_NewType1], _NewType2],
) -> None:
    assert mappable.map(first).map(second) == mappable.map(
        compose(first, second),
    )
```

And it never passes! Because each time `first(x)` and `second(y)` returns a different result.

My work-around for now is this custom strategy:

```python
_func_template = """
lambda {0}: ...
"""

def functions(data: st.DataObject):
        def factory(typ):
            *arg_types, return_type = typ.__args__
            return_value = data.draw(st.from_type(return_type))
            args = []
            for i, arg in enumerate(arg_types):
                args.append('arg{0}'.format(i + 1))

            func = eval(_func_template.format(
                ', '.join(args),
                # return_type.__name__,
            ))

            return st.functions(
                like=func,
                returns=st.just(return_value),
            )
        return factory
```

And then I register this callback to handle `Callable`, like so: `st.register_type_strategy(Callable, custom_strategies.functions(data))`

So, is there any chance to see pure functions in the core of `st.functions()`?

### Additional contract requirements

- Invalid arguments raise `hypothesis.errors.InvalidArgument`. In particular, a
  non-callable `like`, a `returns` value that is not a `SearchStrategy`, and a
  non-boolean `pure` value all raise `InvalidArgument`.
