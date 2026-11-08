Error in `float_generic_pkg-body.vhd`
Many errors are raised for the `float_generic_pkg-body.vhd` (and similar files). This should not happen as the file is part of the standard.
The error probably traces back to line 75 of the `float_generic_pkg.vhd`:
```vhdl
use fixed_pkg.all;
```
This line causes the issue 'Invalid prefix for selected name'.
I'm unsure whether this is a regression issue or whether the 'all' prefix for generic package instances was never properly supported. Either way, this should be fixed.

### Additional contract requirements

Declarations from a generic package instance used as the prefix of a `use ... .all` clause must be potentially visible as unqualified names in the enclosing declarative region.
