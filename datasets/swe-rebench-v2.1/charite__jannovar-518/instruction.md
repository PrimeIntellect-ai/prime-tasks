Problem parsing HGVS `delins`
I'm attempting to parse `NC_000007.14:g.32386323_32386325delGCins`, which arguably is invalid because it's missing the inserted sequence, but the parser is seeing the `GC` as the inserted sequence.

Running:
```
HGVSParser hgvsParser = new HGVSParser();
SingleAlleleNucleotideVariant variant = (SingleAlleleNucleotideVariant)
  hgvsParser.parseHGVSString("NC_000007.14:g.32386323_32386325delGCins");
System.out.println(variant.getChange().toHGVSString());
```

Produces: `32386323_32386325delinsGC`

Which is definitely wrong.

### Additional contract requirements

- The parser must accept `NM_000138.4:c.247_248delATins`, `NM_000138.4:c.247+1_247+3delATins`, `NM_000138.4:c.247-3_247-1delATins`, `NM_000138.4:c.*247_*247+3delATins`, and `NM_000138.4:c.-247_-247-3delATins` as `SingleAlleleNucleotideVariant` values, and each value's `toHGVSString()` must exactly reproduce its input, including the terminal `ins`.
