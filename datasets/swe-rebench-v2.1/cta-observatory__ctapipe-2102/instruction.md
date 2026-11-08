Move validation of class enum trait to run time instead of import time
**Please describe the use case that requires this feature.**

Currently, we define class traitlets like this:

```
class Foo(Component):
    bar_type = create_class_enum_trait(Bar...).tag(config=True)
```

this runs at import time of Foo. Which makes it impossible to use subclasses of `Bar` that are only imported at a later stage.

This is problematic for subclasses defined in other submodules than the base class and the containing component.

THis was triggered by the machine learning module, where `ShowerProcessor` has a class enum trait of `Reconstructor` but because `ctapipe.ml.sklearn` cannot import `Reconstructor` without also importing `ShowerProcessor` (as `ctapipe.reco.__init__` imports it), the ml reconstructors are not yet defined when the class enum trait is created.

This is even more problematic for the case of plugins.

**Describe the solution you'd like**

[HIDDEN]

### Additional contract requirements

- For a class enum trait, determine whether a supplied class name is available when its value is validated, not when the trait is declared. Accept names of eligible subclasses that become available after trait declaration, and reject names that do not identify an eligible subclass at validation time.
