Rename `IDGenerator` transformer to `IndexGenerator`
### Problem Description
Currently the [IDGenerator transformer](https://docs.sdv.dev/rdt/transformers-glossary/id/idgenerator) is used to create an ID column from scratch when it represents an ordered index (`0, 1, 2, 3, ...`) with optional prefixes and suffixes (eg. `id_0, id_1, id_2, ...`.

While this transformer is useful for certain types of datasets, the name **IDGenerator** is not very descriptive of what it's doing. There can be many different ways to generate IDs (which we eventually plan to add); creating ordered indices is just one such way.

### Expected behavior
Rename the `IDGenerator` to `IndexGenerator` to make it clear that this transformer is specifically for ID columns that are indices.

Note that RDT transformers _should_ be backwards compatible. So if someone is still using `IDGenerator` in their code, we should throw a `FutureWarning` explaining that it has been deprecated. However, the code can continue to work, using the `IndexGenerator` under-the-hood instead.

```python
>>> from rdt.transformers.id import IDGenerator
>>> transformer = IDGenerator(prefix='id_', starting_value=0)
FutureWarning: The 'IDGenerator' has been renamed to 'IndexGenerator'.
```

### Additional contract requirements

- The warning line shown in the example is abbreviated; the complete `FutureWarning` message must be exactly: `The 'IDGenerator' has been renamed to 'IndexGenerator'. Please update thename to ensure compatibility with future versions of RDT.`
