Can't resolve imported const in generic interface modport
version: https://github.com/veryl-lang/veryl/commit/978fdb0ab7453bf206e3c6a381eca7c5f5fe678c

top.veryl
```sv
import pkg::*;

module Top {
    inst m : myif::<XLEN>;
}
```
pkg.veryl
```sv
package pkg {
    const XLEN :u32 = 32;
}
```
myif.veryl
```sv
interface myif::<WIDTH: const> {
    var data : logic<WIDTH>;
    modport master {
        data : output,
    }
}
```

```
Error: undefined_identifier (link)

  × XLEN is undefined
  [Failed to read contents for label `Error location` (offset: 54, length: 5): OutOfBounds]
  help:
```

Using pkg::XLEN instead of XLEN compiles successfully.
