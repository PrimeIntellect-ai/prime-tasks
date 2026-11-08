PhpdocTypesOrderFixer false positive
The fixer wants to update this:

```
	/**
	 * @return MultiMap<CompositeKey<Identity, ScalarKey>, CompensationAllocation>
	 */
```

to this:

```
	/**
	 * @return MultiMap<CompositeKey<Identity, ScalarKey>|, CompensationAllocation>
	 */
```
