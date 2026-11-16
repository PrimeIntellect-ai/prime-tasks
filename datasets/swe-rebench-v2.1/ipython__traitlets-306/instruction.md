`Dict` trait is lacking a way to constrain all keys with a single trait
Coming from the original traits, I am used to `tr.Dict(TraitAppliedToKeys,TraitAppliedToValues)`. This functionality is lacking in traitlets. When describing a mathematical map, the two trait specifications would specify the domain and image of the map.
Obviously, this trait instead offers the functionality of something that I'd call _lightweight object specification_, where the keys are essentially fixed values. To me, that describes less of a mapping, but really more of a set of (typically named?) properties. Maaybe we should have two aliases `Mapping` and `PropertySet`, both describing instances of dict?

### Additional contract requirements

- `Dict` must accept an optional `key_trait` argument, a trait that validates every key in the dictionary.
