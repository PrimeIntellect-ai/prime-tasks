Consider restricting Levels to columns with categorical scitype
Currently the Levels transform contributed by @Frank-III and refactored by @eliascarv can operate directly on any type of column, including columns with the wrong scitype. I think we could consider a more consistent approach where we ask users to be explicit about the scitypes using the Coerce transform first. Even though this is a breaking change, it will provide more safety in real-world applications of pipelines.

### Additional contract requirements

- When `Levels` is applied to a selected non-categorical column, it must throw an `AssertionError`.
