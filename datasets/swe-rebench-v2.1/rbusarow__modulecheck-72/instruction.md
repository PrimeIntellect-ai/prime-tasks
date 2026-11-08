DisableViewBinding throws false positive if a generated binding is consumed in another module
`:moduleA` has a layout which is not consumed within that module.
`:moduleA` has viewBinding enabled.
`:moduleB` depends upon `:moduleA`.
`:moduleB` has viewBinding disabled.
`:moduleB` uses the binding object from `:moduleA`.

expected: no changes suggested
actual: suggests disabling viewBinding in `:moduleA`.
