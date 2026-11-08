ENH: implement `new_moltype.MolType.degenerate_from_seq`
this will be necessary for integration of new style modules with code performing alignment

### Additional contract requirements

- Interpret existing ambiguity symbols as the sets of residues they represent. For inputs without gaps or missing symbols, return the most specific symbol in the moltype’s alphabet whose represented set contains all residues represented by the input characters; this applies to both nucleic-acid and protein moltypes.
- An input consisting only of gaps returns the moltype’s gap symbol. A gap mixed with other characters, or a missing symbol in the input, yields the moltype’s missing symbol.
