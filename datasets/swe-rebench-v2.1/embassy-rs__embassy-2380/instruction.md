embassy task: cannot cfg away task arguments

```rust
#[embassy_executor::task]
pub async fn test(
    a: u32,
    b: u32,
    #[cfg(feature = "c")] c: u32,
) {

}
```

Fails with `cannot find value c in this scope` when the feature `c` is not enabled. It seems argument `cfg`'s are not applied during the transformation.

### Additional contract requirements

- The `#[embassy_executor::task]` attribute generates a function with the same name as the annotated async function. The generated function takes the task's arguments, omitting any argument whose `#[cfg]` condition evaluates to false, and returns an `embassy_executor::SpawnToken` that can be passed to an executor's spawner to run the task.
