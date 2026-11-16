type inference of return value in async fn
```rust
async fn get_accounts() -> Result<Vec<String>, ()> {
    let accounts = Vec::<String>::new().iter().map(|x| x.clone()).collect();
    //  ^ Vec<String> but r-a infers {unknown}
    Ok(accounts)
}
```

This works without async.

rust-analyzer: 5a1fd0576 2021-05-26
rustc 1.54.0-nightly (3e99439f4 2021-05-17)
