Existential operator
In flow 0.72 the `*` (existential) operator was deprecated, see https://github.com/facebook/flow/blob/master/Changelog.md#0720.  Since much of our code still use this operator we should handle it.  Converting it to `any` seems reasonable.
