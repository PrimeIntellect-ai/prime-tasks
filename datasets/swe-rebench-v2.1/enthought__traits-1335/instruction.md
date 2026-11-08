Don't hard-code class names in TraitListEvent.__repr__ and similar __repr__ implementations
We currently hardcode the `TraitListEvent` class name in `TraitListEvent.__repr__`; [HIDDEN], so that subclasses don't have a misleading `__repr__`. See https://github.com/enthought/traits/blob/786a39ee9a94f925e10a602b84fdc17b1895816a/traits/trait_list_object.py#L57

I haven't checked other `__repr__`s, but we will almost certainly need to update `TraitDictEvent` and `TraitSetEvent` similarly, and possibly others, too.

Ref: enthought/envisage#352

### Additional contract requirements

- `TraitListEvent.__repr__`, `TraitDictEvent.__repr__`, and `TraitSetEvent.__repr__` must identify the concrete runtime class, so a subclass instance is not represented as its base event class. This requirement is limited to those three event representations; other `__repr__` implementations are outside its scope.
