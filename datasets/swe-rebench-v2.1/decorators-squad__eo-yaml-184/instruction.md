Add YamlNode:value(YamlNode) to YamlMapping
YamlMapping should have a generic ``YamlNode : value(key:YamlNode)`` to fetch a value mapped to a key.

### Additional contract requirements

A lookup key may be any `YamlNode`, including a scalar, mapping, or sequence. When the key is present, the lookup returns the node associated with that key.
