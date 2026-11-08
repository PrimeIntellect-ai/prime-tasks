Consider renaming `Buf::bytes()` and `BufMut::bytes_mut()`
These two functions are named in a way that implies they return the *entire* set of bytes represented by the `Buf`/`BufMut`.

Some options:

* `window()` / `window_mut()`
* `chunk()` / `chunk_mut()`.
* `fragment()` / `fragment_mut()`

### Additional contract requirements

Rename `Buf::bytes()` to `Buf::chunk()` and `BufMut::bytes_mut()` to `BufMut::chunk_mut()`. Each renamed method must preserve the behavior of its predecessor, exposing the current readable or writable region, respectively.
