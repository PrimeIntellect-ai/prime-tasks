Panic in do_parse with take
Hi,

The following parser:
```rust
named!(parser02<&[u8],()>,
    do_parse!(
        hdr: take!(1) >>
        data: take!(18446744073709551615) >>
        ( () )
    )
);

#[test]
fn test02() {
    let data = b"0\x88\xff\xff\xff\xff\xff\xff\xff\xff00\x0f\x02\x000\x00\x00\x00\x00\x00\x0000\x0f\x00\xff\x0a\xbb\xff";
    let _ = parser02(data);
}
```

fails with an error:
```
thread 'test02' panicked at 'attempt to add with overflow', <do_parse macros>:33
```

The backtrace is not interesting, so not reported here.

The bug was originally discovered in https://github.com/rusticata/x509-parser/issues/1

### Additional contract requirements

- The parser above must not panic. Instead, when the requested length would overflow the computation of the needed size, it must return `IResult::Incomplete(Needed::Unknown)`.
