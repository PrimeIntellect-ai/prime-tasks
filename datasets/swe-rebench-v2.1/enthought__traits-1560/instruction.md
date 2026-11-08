Decorating a static listener with @on_trait_change causes problems
This minimal example fails on Python 3.6.0 and Traits 5.1.2:
```python
from traits.api import HasTraits, List, on_trait_change

class TestBase(HasTraits):
    foo = List()

    @on_trait_change('foo_items')
    def _foo_changed(self, obj, trait_name, undefined, event):
        pass

class PatchedBaseClass(TestBase):
    pass
```

Here's the error:
```
Traceback (most recent call last):
  File "test.py", line 13, in <module>
    class PatchedBaseClass(TestBase):
  File "/Users/jwiggins/.edm/envs/edm3/lib/python3.6/site-packages/traits/has_traits.py", line 489, in __new__
    class_name, bases, class_dict, is_category=False
  File "/Users/jwiggins/.edm/envs/edm3/lib/python3.6/site-packages/traits/has_traits.py", line 831, in update_traits_class_dict
    _add_notifiers(trait._notifiers(1), handlers)
  File "/Users/jwiggins/.edm/envs/edm3/lib/python3.6/site-packages/traits/has_traits.py", line 429, in _add_notifiers
    handler = StaticTraitChangeNotifyWrapper(handler)
  File "/Users/jwiggins/.edm/envs/edm3/lib/python3.6/site-packages/traits/trait_notifiers.py", line 373, in __init__
    % (handler.__name__, arg_count)
traits.trait_errors.TraitNotificationError: Invalid number of arguments for the static anytrait change notification handler: _foo_changed. A maximum of 4 arguments is allowed, but 5 were specified.
```

### Additional contract requirements

- A public decorator `observe(trait_names)` is available from `traits.api`. `trait_names` is a string or an iterable of strings naming the trait(s) to observe. Applied to a method, it registers that method to be called with a single `TraitChangeEvent` argument each time one of the named traits changes; the method signature is `(self, event)`.
- `TraitChangeEvent` is a public class whose instances expose the attributes `object`, `name`, `old` and `new`, describing the object on which the change occurred, the name of the changed trait, and the old and new values.
- A method decorated with `observe` or with `on_trait_change` is registered only through the decorator: the special `_<name>_changed` naming convention is suppressed for that method, so the method is invoked exactly once per change and is not additionally invoked as a magic-named handler.


- For an `on_trait_change("foo")` handler declared as `def handler(self, obj, name, old, new)`, changing `foo` from 0 to 23 calls it with `(obj, "foo", 0, 23)`. For an `on_trait_change("foo_items")` handler declared as `def handler(self, obj, trait_name, undefined, event)`, appending 23 to `foo` passes the changed object as `obj`, `"foo_items"` as `trait_name`, and an event with `event.added == [23]`.
