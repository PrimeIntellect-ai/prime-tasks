Possible syntax error in gml.py (readwrite)
https://github.com/networkx/networkx/blob/e3566e53793cdccc19a8c2ff9c056e0d7b524634/networkx/readwrite/gml.py#L680

I've got an error when I want to write a .gml file from a network using the write_gml() function. [HIDDEN]

### Additional contract requirements

- `write_gml()` should successfully write the affected network to a GML file without a serialization error.
- For a node with a floating-point label, its GML label must contain the text representation of that value (for example, a node labeled `1.0` should have the GML label `1.0`).
