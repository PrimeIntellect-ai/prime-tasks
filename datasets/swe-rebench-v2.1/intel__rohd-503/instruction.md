Provide API to access the "driver" of `Module` `input` and `inOut` ports
### Motivation

When `addInput`, `addInputArray`, `addInOut`, or `addInOutArray` is created, a source to drive the input is required in the API call.  This is fundamental to the way ROHD is able to identify hierarchy and connectivity between Modules (https://intel.github.io/rohd-website/docs/modules/).

Determining the "original" driver of a call to `addInput` is trivial, since you can just call `srcConnection`.  However, for the other three APIs listed, it is not trivial.  [HIDDEN]  For the `inOut` APIs, it's even more complicated (and maybe impossible, depending on connectivity generated afterwards) to determine who the "original" driver was programmatically since inOut wires can have multiple drivers (note that the `build()` analysis already has to do some extra book-keeping on inOuts to properly determine hierarchy).

Knowing the original driver of an input/inOut to a Module is useful for many reasons, some of which are:
- Creating an input/inout port and connecting it to a driver later
- Finding the driver of an input/inout of a sub-module and using it to fan out drivers to other sub-modules
- Automation that benefits from identifying the version of an input/inOut "outside of" the module that owns the port
- Determining easily whether an input is left floating in a programmatic way



### Desired solution

Add an API like `inputDriver` and `inOutDriver` (name subject to change) that provides the "original driver", the external version, of a port with the same name as `input` or `inOut`.

### Alternatives considered

Leave it up to users to figure out and automate per their needs

### Additional details

_No response_

### Additional contract requirements

- `Module` exposes `inputSource(String name)`, which returns the original external `Logic` (or `LogicArray`) that was passed as `source` when the input port `name` was created with `addInput` or `addInputArray`.
- `Module` exposes `inOutSource(String name)`, which returns the original external `Logic` (or `LogicArray`) that was passed as `source` when the inOut port `name` was created with `addInOut` or `addInOutArray`.
- Both accessors return the same object that was supplied (identity, not a copy), for both scalar and array ports.
- Both accessors throw a `PortDoesNotExistException` when no port with that name exists.
