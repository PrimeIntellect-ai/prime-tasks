Make some fields in manifests optional
Many of these fields (e.g. Footprint, ProductionConditions, Seedling) have sensible defaults. We should allow users to not specify these, and infer their value instead.

### Additional contract requirements

The following fields may be omitted from a manifest entry, and their value is inferred:

- In a recipe manifest entry, the `conditions` field may be omitted. When omitted, it is inferred to be the default `RecipeConditions`: `workers_required` of `0` and no `allowable_light_range`.
- In a structure manifest entry, the `footprint` field may be omitted. When omitted, it is inferred to be a single-tile footprint (the same value as `Footprint::single()`).

A manifest that omits these fields must deserialize successfully, and the processed `RecipeData` / `StructureData` must contain the inferred defaults.
