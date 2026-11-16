Binary expression does not type check function parameters
The following example produces no diagnostics:
```vhdl
package foo is
    function takes_slv(din : bit_vector) return boolean;
    constant bar : boolean := takes_slv(true) and true;
end package;
```
even though a diagnostic similar to 'true' does not match array type 'BIT_VECTOR'` should be reported.
The following example produces the expected output:

```vhdl
package foo is
    function takes_slv(din : bit_vector) return boolean;
    constant bar : boolean := takes_slv(true);
end package;
```

### Additional contract requirements

- The diagnostic message must be exactly `'true' does not match array type 'BIT_VECTOR'`.
