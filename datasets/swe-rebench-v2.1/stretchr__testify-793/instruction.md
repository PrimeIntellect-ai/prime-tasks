didPanic does not detect panic(nil)
This is because you use `recover() != nil` to detect whether a panic  occurred.
I have opened PR  #793 to fix this.

### Additional contract requirements

- `didPanic` must return `true` and a nil panic message when its function calls `panic(nil)`. `PanicsWithValue` must return `true` when the expected value is nil and the function calls `panic(nil)`.
- - For a non-nil panic, `didPanic` must return the panic value as its message; for example, `panic("Panic!")` must produce the message `"Panic!"`.
