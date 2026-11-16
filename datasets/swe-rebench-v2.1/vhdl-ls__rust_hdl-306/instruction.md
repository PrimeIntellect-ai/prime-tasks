Unused lint not available in vhdl_lang
I really like the new control over lint severities and am looking at adding linting to our CI using the `vhdl_lang` executable.

However, the unused declaration detection has a special case applied to it which seems to override the `[lint]` settings.

Example `vhdl_ls.toml`:
```toml
...
[lint]
unused = 'error'
```

Example file (not set as a library file)
```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity UnusedExample is
    port (
        In1_i: in std_logic;
        In2_i: in std_logic;
        Out_o: out std_logic
    );
end UnusedExample;

architecture behavioural of UnusedExample is
    signal used_s: std_logic;
    signal unused_s: std_logic;
begin
    used_s <= In1_i or In2_i;
    Out_o <= used_s;
end behavioural;
```

In VSCode the error is flagged correctly (and the severity has been upgraded to error)
![image](https://github.com/VHDL-LS/rust_hdl/assets/6715247/1dca1d91-1db2-4cc0-b12b-6cd78cb51dca)
But running `vhdl_lang` gives no diagnostics.

I'm using v0.79.0.

[HIDDEN]
