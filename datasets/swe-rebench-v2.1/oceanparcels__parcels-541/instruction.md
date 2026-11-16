c-code generator for if-statements inside custom kernels
Hi all,

There seems to be a bug in the c-code generator when using if-statements inside a custom kernel. I'll attach a sample script based on the stommel example and the corresponding c-code.

When I put an if-statement inside of another if-statement, the code inside of the if-statement (see l. 134-136 c-code) seems to get executed before the if-statement itself is checked (l. 137). The corresponding if-statement in the python code can be found on l. 91-92.

Best,
Mikael

[0d46b78f1f104285b3dc199479ae9038.c.txt](https://github.com/OceanParcels/parcels/files/2884289/0d46b78f1f104285b3dc199479ae9038.c.txt)

[Stommel.py.txt](https://github.com/OceanParcels/parcels/files/2884293/Stommel.py.txt)

### Additional contract requirements

Generated C code for nested `if` statements must preserve their conditional behavior: an inner body runs only when its own condition and every enclosing condition are true.
