Aliases are limited
If you define `Alias: systemCPN = example.com`, then you can use that alias in some places, but not others. For example, you could use the alias in a code, like `someCode#systemCPN`, but you could not use the alias when fixing a value, `* identifier[0].system = systemCPN`. It may be better to expand the usefulness of aliases by allowing them to appear in more places.
