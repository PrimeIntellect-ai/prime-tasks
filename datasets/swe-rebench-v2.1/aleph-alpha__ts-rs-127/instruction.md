Type overrides ignored for newtype enum variants in internal and adjacent representations
Hi,
Thanks for your work on ts-rs.

Currently the `#[ts(type = "something")]` overrides are not used for newtype variants for enums that use internal or adjacent representations:

```rs
#[derive(Serialize)]
struct S;

// compiles
#[derive(TS, Serialize)]
enum External {
    Newtype(#[ts(type = "unknown")] S),
}

// error[E0277]: the trait bound `S: TS` is not satisfied
#[derive(TS, Serialize)]
#[serde(tag = "tag")]
enum Internal {
    Newtype(#[ts(type = "unknown")] S),
}

// error[E0277]: the trait bound `S: TS` is not satisfied
#[derive(TS, Serialize)]
#[serde(tag = "tag", content = "content")]
enum Adjacent {
    Newtype(#[ts(type = "unknown")] S),
}
```
The code that causes this behaviour (for adjacent enums) is at https://github.com/Aleph-Alpha/ts-rs/blob/d59ca01878ce03f7b62ff0be56b350808fd257ed/macros/src/types/enum.rs#L97-L100

[HIDDEN]

### Additional contract requirements

- For internally tagged and adjacently tagged enums, a newtype variant's `#[ts(type = "...")]` override must be honored when generating its TypeScript type. This must not require the underlying field type to implement `TS`.
