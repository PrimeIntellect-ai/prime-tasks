Sort ports in generated outputs
### Motivation

Currently the order of ports in generated SystemVerilog is somewhat random, which can make integration of the generated code a little annoying.  It would be nice if the ports were organized.

### Desired solution

It might be reasonable to sort them by name alphabetically, perhaps grouped only by name or maybe keeping inputs above outputs.  Usually related ports might have the same prefix.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- In generated SystemVerilog, declare input ports alphabetically by name, followed by output ports alphabetically by name, followed by internal signals alphabetically by name. For submodule instances, list input port connections alphabetically by port name before output port connections alphabetically by port name.
