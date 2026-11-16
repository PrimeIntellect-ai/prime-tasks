`der` crate fails to emit implicit context-specific tags on `SET`
There is a bug with the generated DER somewhere in the `der` crate. I discovered this while writing a `pkcs10` crate. This causes the encoding tests to fail. Specifically, it fails to correctly emit the `IMPLICIT` tag modification of the `SET` in `CertReqInfo::attributes` (see tagged PR). Decoding works correctly.

The fix is probably simple, but I don't know enough about the structure of the `der` crate to find it easily. And since I'm not sure you actually want this PR, I didn't spend a lot of time on it. I'm willing to produce a patch if you point me in the right direction.

The following code triggers the bug:

```
#[derive(Clone, Debug, PartialEq, Eq, Sequence)]
pub struct Foo {
    #[asn1(context_specific = "0", tag_mode = "IMPLICIT")]
    pub bar: SetOfVec<Baz>,
}
```

Decoding of the above code works correctly. But encoding causes `SET` to be emitted without the context-specific `0` tag.

### Additional contract requirements

For a `Sequence` struct with a field declared as

```rust
#[asn1(context_specific = "0", tag_mode = "IMPLICIT")]
pub bar: SetOfVec<Baz>,
```

encoding must emit the field with the context-specific constructed tag `[0]`
(the tag octet `0xA0`) instead of the universal `SET` tag (`0x31`), while
decoding must continue to accept the context-specific form.

Concretely, a struct containing a single `SetOfVec` element whose DER encoding
is `06 07 2A 86 48 CE 3D 02 01` must encode as
`30 0B A0 09 06 07 2A 86 48 CE 3D 02 01`.
