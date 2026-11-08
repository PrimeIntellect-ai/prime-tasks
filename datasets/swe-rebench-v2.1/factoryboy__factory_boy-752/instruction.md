'Options' object has no attribute 'pre_declarations' is too ambiguous
#### The problem
Typo incorrectly specifying the Model for a Factory.

#### Proposed solution
Check if any specified factories are actually Models, in which case give a more clear error message.

#### Extra notes
Thanks for the good work on this neat lib!

### Additional contract requirements

- A `factory.SubFactory` given a class that is not a `factory.BaseFactory` subclass (for example a model class) must, when the parent factory is built, raise `factory.errors.AssociatedClassError`.
- The string representation of that error must mention both the offending class name and the name of the factory that declared the `SubFactory`.
- A `factory.SubFactory` given a valid `factory.BaseFactory` subclass must build the related object by invoking that sub-factory when the parent factory is built.
