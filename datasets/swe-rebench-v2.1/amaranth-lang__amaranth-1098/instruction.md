Consistently use "comb" for combinatorial domain instead of sometimes "comb" and sometimes None
This simplifies the types (all of the domain dicts have strings as keys, instead of sometimes strings and sometimes NoneType), makes the codebase easier to understand, and aligns designer-visible and internal designators.

### Additional contract requirements

- `Fragment.add_driver(signal, domain="comb")` and `Fragment.add_statements(domain, *stmts)` in `amaranth.hdl._ir` require `domain` to be a string; passing a non-string value such as `None` raises `AssertionError`.
