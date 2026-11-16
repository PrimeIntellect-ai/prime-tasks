`hypothesis@6.14.8` stopped working for `dry-python/returns`
Dependabot PR, that updates version `6.14.7` to `6.14.8`, revealed that hypothesis has stopped working for us: https://github.com/dry-python/returns/pull/1028/checks?check_run_id=3351483158

Previous version did work fine: https://github.com/dry-python/returns/commit/50f06330c00c5c8a5538b192bb73bed109a052a0

Logs:
```
You can reproduce this example by temporarily adding @reproduce_failure('6.14.8', b'AA==') as a decorator on your test case
_______________________ test_pair_altablen_identity_law ________________________

    def factory(source: st.DataObject) -> None:
>       with type_vars():

returns/contrib/hypothesis/laws.py:204:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
.venv/lib/python3.9/site-packages/hypothesis/core.py:624: in execute_once
    result = self.test_runner(data, run)
.venv/lib/python3.9/site-packages/hypothesis/executors.py:52: in default_new_style_executor
    return function(data)
.venv/lib/python3.9/site-packages/hypothesis/core.py:620: in run
    return test(*args, **kwargs)
returns/contrib/hypothesis/laws.py:204: in factory
    with type_vars():
.venv/lib/python3.9/site-packages/hypothesis/core.py:562: in test
    result = self.test(*args, **kwargs)
returns/contrib/hypothesis/laws.py:207: in factory
    source.draw(st.builds(law.definition))
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/core.py:1639: in draw
    result = self.conjecture_data.draw(strategy)
.venv/lib/python3.9/site-packages/hypothesis/internal/conjecture/data.py:871: in draw
    strategy.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:400: in validate
    self.do_validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/lazy.py:135: in do_validate
    w.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/core.py:792: in validate
    fixed_dictionaries(self.kwargs).validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:400: in validate
    self.do_validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/lazy.py:135: in do_validate
    w.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:400: in validate
    self.do_validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:800: in do_validate
    self.mapped_strategy.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:400: in validate
    self.do_validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/collections.py:46: in do_validate
    s.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:400: in validate
    self.do_validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/lazy.py:135: in do_validate
    w.validate()
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:401: in validate
    self.is_empty
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:135: in accept
    recur(self)
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/strategies.py:131: in recur
    mapping[strat] = getattr(strat, calculation)(recur)
.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/deferred.py:70: in calc_is_empty
    return recur(self.wrapped_strategy)
            return st.from_type(annotated_type)
        # Now, confirm that we're dealing with a generic type as we expected
        if sys.version_info[:2] < (3, 9) and not isinstance(
            thing, typing_root_type
        ):  # pragma: no cover
            raise ResolutionFailed(f"Cannot resolve {thing} to a strategy")

        # Some "generic" classes are not generic *in* anything - for example both
        # Hashable and Sized have `__args__ == ()` on Python 3.7 or later.
        # (In 3.6 they're just aliases for the collections.abc classes)
        origin = getattr(thing, "__origin__", thing)
        if (
            typing.Hashable is not collections.abc.Hashable
            and origin in vars(collections.abc).values()
            and len(getattr(thing, "__args__", None) or []) == 0
        ):
            return st.from_type(origin)

        # Parametrised generic types have their __origin__ attribute set to the
        # un-parametrised version, which we need to use in the subclass checks.
        # e.g.:     typing.List[int].__origin__ == typing.List
        mapping = {
            k: v
            for k, v in _global_type_lookup.items()
            if is_generic_type(k) and try_issubclass(k, thing)
        }
        if typing.Dict in mapping or typing.Set in mapping:
            # ItemsView can cause test_lookup.py::test_specialised_collection_types
            # to fail, due to weird isinstance behaviour around the elements.
            mapping.pop(typing.ItemsView, None)
            if sys.version_info[:2] == (3, 6):  # pragma: no cover
                # `isinstance(dict().values(), Container) is False` on py36 only -_-
                mapping.pop(typing.ValuesView, None)
        if typing.Deque in mapping and len(mapping) > 1:
            # Resolving generic sequences to include a deque is more trouble for e.g.
            # the ghostwriter than it's worth, via undefined names in the repr.
            mapping.pop(typing.Deque)
        if len(mapping) > 1:
            # issubclass treats bytestring as a kind of sequence, which it is,
            # but treating it as such breaks everything else when it is presumed
            # to be a generic sequence or container that could hold any item.
            # Except for sequences of integers, or unions which include integer!
            # See https://github.com/HypothesisWorks/hypothesis/issues/2257
            #
            # This block drops ByteString from the types that can be generated
            # if there is more than one allowed type, and the element type is
            # not either `int` or a Union with `int` as one of its elements.
            elem_type = (getattr(thing, "__args__", None) or ["not int"])[0]
            if getattr(elem_type, "__origin__", None) is typing.Union:
                union_elems = elem_type.__args__
else:
                union_elems = ()
            if not any(
                isinstance(T, type) and issubclass(int, T)
                for T in list(union_elems) + [elem_type]
            ):
                mapping.pop(typing.ByteString, None)
        elif (
            (not mapping)
            and isinstance(thing, ForwardRef)
            and thing.__forward_arg__ in vars(builtins)
        ):
            return st.from_type(getattr(builtins, thing.__forward_arg__))
        strategies = [
            v if isinstance(v, st.SearchStrategy) else v(thing)
            for k, v in mapping.items()
            if sum(try_issubclass(k, T) for T in mapping) == 1
        ]
        empty = ", ".join(repr(s) for s in strategies if s.is_empty)
        if empty or not strategies:
>           raise ResolutionFailed(
                f"Could not resolve {empty or thing} to a strategy; "
                "consider using register_type_strategy"
            )
E           hypothesis.errors.ResolutionFailed: Could not resolve returns.interfaces.altable.AltableN[~_FirstType, ~_SecondType, ~_ThirdType] to a strategy; consider using register_type_strategy

.venv/lib/python3.9/site-packages/hypothesis/strategies/_internal/types.py:334: ResolutionFailed
---------------------------------- Hypothesis ----------------------------------
Falsifying example: factory(
    source=data(...),
)
```
