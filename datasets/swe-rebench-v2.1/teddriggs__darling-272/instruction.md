Flatten fields should combine unknown items from across multiple attributes
The current placement of the initializer for a `flatten`ed field has two problems:

1. If there are multiple attributes, only unknown items from the last attribute will be reflected in the returned value of the flattened field.
2. If there are no attributes, there will be a spurious error for the flattened field being uninitialized
