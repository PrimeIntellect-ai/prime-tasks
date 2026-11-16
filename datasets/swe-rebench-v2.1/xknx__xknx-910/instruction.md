ISO 8859-1 String support (Latin-1)
- support DPT 16.001 ISO 8859-1 strings

currently we only support DPT 16.000 but I think we encode/decode it as Unicode (`char()`) instead of just ASCII.

### Additional contract requirements

Expose the DPT 16.001 codec from `xknx.dpt` as `DPTLatin1`. It must be identifiable as DPT 16.001, distinct from DPT 16.000.
