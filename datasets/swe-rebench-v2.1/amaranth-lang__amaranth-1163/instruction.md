Make Pin an interface object
Right now it's a weird hybrid of a Record and an interface object.

### Additional contract requirements

`amaranth.lib.io` provides a public class `Pin` that is an interface object: a subclass of
`amaranth.lib.wiring.PureInterface`.

`Pin.Signature(width: int, dir: str, *, xdr: int = 0)` is a public signature class. `width` and
`xdr` are non-negative integers, and `dir` is one of `"i"`, `"o"`, `"oe"`, `"io"`. Its members are:

- `i` (input, width `width`) when `dir` is `"i"` or `"io"` and `xdr` is 0 or 1; otherwise `i0`,
  `i1`, ... (inputs, width `width`, one per gear) when `dir` is `"i"` or `"io"` and `xdr` is
  greater than 1;
- `i_clk` (output, width 1) when `dir` is `"i"` or `"io"` and `xdr` is nonzero;
- `i_fclk` (output, width 1) when `dir` is `"i"` or `"io"` and `xdr` is greater than 2;
- `o` (output, width `width`) when `dir` is `"o"`, `"oe"`, or `"io"` and `xdr` is 0 or 1;
  otherwise `o0`, `o1`, ... (outputs, width `width`, one per gear) when `dir` is `"o"`, `"oe"`, or
  `"io"` and `xdr` is greater than 1;
- `o_clk` (output, width 1) when `dir` is `"o"`, `"oe"`, or `"io"` and `xdr` is nonzero;
- `o_fclk` (output, width 1) when `dir` is `"o"`, `"oe"`, or `"io"` and `xdr` is greater than 2;
- `oe` (output, width 1) when `dir` is `"oe"` or `"io"`.

A `Pin.Signature` exposes its parameters as attributes `width`, `dir`, and `xdr`.

`Pin(width: int, dir: str, *, xdr: int = 0, path=None, src_loc_at=0)` creates an interface object
whose `signature` is a `Pin.Signature` built from `width`, `dir`, and `xdr`. `path` names the
created signals; `src_loc_at` shifts the stack frame used to derive the signal names when `path`
is not given. `Pin.width`, `Pin.dir`, and `Pin.xdr` are read-only properties returning the
corresponding signature parameters.

`amaranth.lib.wiring.Signature.is_compliant(interface)` returns `True` if and only if the
interface's signature matches the signature it is called on.

`amaranth.lib.wiring.flipped(obj)` returns a `FlippedInterface` view of `obj` with all member flow
directions reversed.

`amaranth.build.res.ResourceManager.request(...)` returns an interface object (a `PureInterface`,
or a flipped `Pin`) instead of a `Record`.
