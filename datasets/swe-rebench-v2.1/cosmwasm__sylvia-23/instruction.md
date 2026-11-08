Generate the `const fn messages() -> [&'static str; N]` function returning generated messages variants
The function should be generated for both query and exec messages. The idea is to be able to use them to verify if message variants collide, and do it in compile time. For example, consider the following trait:

```rust
#[sylvia::interface]
pub trait Group {
  type Error: From<StdError>;

  #[msg(exec)]
  fn update_admin(&self, ctx: ExecCtx, admin: Option<String>) -> Result<Response, Self::Error>;

  #[msg(exec)]
  fn update_members(&self, ctx: ExecCtx, remove: Vec<String>, add: Vec<Member>) -> Result<Response, Self::Error>;

  #[msg(query)]
  fn member(&self, ctx: QueryCtx, addr: String) -> Result<MemberResp, Self::Error>;
}
```

The following should be generated:

```rust
impl ExecMsg {
  const fn messages() -> [&'static str; 2] {
    ["update_admin", "update_members"]
  }
}

impl QueryMsg {
  const fn messages() -> [&'static str; 1] {
    ["member"]
  }
}
```

Note, that it is probably beneficial to keep all items sorted internally (so it would be linear to look for name collisions).

### Additional contract requirements

- The generated function is public: `pub const fn messages() -> [&'static str; N]` on the generated `ExecMsg` and `QueryMsg` enums.
- `N` is the number of message variants in the enum.
- Each element is the snake_case name of the corresponding message variant, in the order the variants are declared.
