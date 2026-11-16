Deprecate and eventually remove SingletonHasTraits and related classes
The `SingletonHasTraits`, `SingletonHasStrictTraits` and `SingletonHasPrivateTraits` classes are unused within Traits or elsewhere in ETS, and promote a dangerous, hard-to-test pattern. We should deprecate them in Traits 6.1.0, and remove them in Traits 7.0.0
