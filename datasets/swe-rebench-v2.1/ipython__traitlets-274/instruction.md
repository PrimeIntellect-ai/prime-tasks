Union trait does not handle trait metadata correctly
If I have a `HasTraits` class, called `Mix`, that has a `Union` trait, called `union`, then since the trait metadata of `union` is a class attribute, all `Mix` instances will have the same metadata for `union`, regardless of the actual trait type of `union`.

This can be harmful if you have a `Union` of traits with different `to_json` for example.

I hope this will be clearer with an example:
```python
from traitlets import Float, Unicode, HasTraits

class Mix(HasTraits):
    union = Float().tag(metadata="I'm a float") | Unicode().tag(metadata="I'm still a float, but with unicode metadata")

mix1 = Mix(union=0)
print mix1.union, mix1.trait_metadata('union', 'metadata')
mix2 = Mix(union='')
print mix1.union, mix1.trait_metadata('union', 'metadata')
```
outputs
```python
0.0 I'm a float
0.0 I'm still a float, but with unicode metadata
```

### Additional contract requirements

- If the active Union member does not provide a value for a metadata key, `trait_metadata` must fall back to the Union trait's metadata for that key. For example, when the Union is tagged with `ti='a'` and the active member has no `ti` tag, `trait_metadata(name, 'ti')` must return `'a'`.
