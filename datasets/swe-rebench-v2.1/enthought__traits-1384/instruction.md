Add NoDefaultSpecified from trait_type to traits.api
This is the constant used to indicate that a trait `__init__` method is not being supplied with a default override.  This is helpful to have available for advanced users who are writing new `TraitType` subclasses and need to handle possible missing `default_value` parameters.
