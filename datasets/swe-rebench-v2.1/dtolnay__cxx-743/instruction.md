Trait impls for CxxString:  Hash, Ord, PartialOrd, Eq
I need to use `&CxxString` as the key of a BTreeMap or HashMap. However there are some trait impls currently missing, [HIDDEN] BTreeMap requires `Ord` and HashMap requires `Hash + Eq`.

### Additional contract requirements

- `CxxString` implements `PartialOrd<str>`, so a `CxxString` can be compared with a `&str` and yields the ordering of their underlying bytes.
- `str` implements `PartialOrd<CxxString>`, so a `&str` can be compared with a `CxxString` and yields the ordering of their underlying bytes.
- For `CxxString` values, equality is determined by equality of their byte contents, and ordering is lexicographic by byte contents. Values equal under this equality must hash consistently.
