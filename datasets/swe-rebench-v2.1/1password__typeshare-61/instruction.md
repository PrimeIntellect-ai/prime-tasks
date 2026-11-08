Double option pattern support
Hello,
I found a missing feature in `typeshare`. Some APIs support partial updates for DTOs. That means that they have a distinction between a missing field and a field equal to `null` eg.:

```rust
#[derive(Serialize, Deserialize, Debug)]
#[typeshare]
pub struct UserUpdateParams {
    pub username: Option<String>,
    pub password: Option<String>,
    #[typeshare(serialized_as = "Option<String>")]
    pub valid_until: Option<OffsetDateTime>,
}
```

When the `valid_until` property is `null` on the database level, it means that the user is valid forever. To support this kind of use case `serde` has a [`double option`](https://docs.rs/serde_with/latest/serde_with/rust/double_option/) pattern.

Unfortunately this is not supported by `typeshare` since `Option<Option<String>>` is compiled as `valid_until?: string` in `TypeScript`. Instead it should be compiled as `valid_until?: string | null`.
