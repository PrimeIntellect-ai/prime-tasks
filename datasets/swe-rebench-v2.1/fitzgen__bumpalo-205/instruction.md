May panic due to unwrap on Err
I've using [afl.rs](https://github.com/rust-fuzz/afl.rs) to fuzz this crate. And I found a panic issue. The code to replay the issue is
```
let mut _local0 = bumpalo::Bump::with_capacity(10995706271387654244);
```
And from the panic reportn, it seems that this panic is caused by use unwrap on a Result which may return err.
![image](https://user-images.githubusercontent.com/58699405/229958760-64185195-66ae-481e-a284-1eaf316c2605.png)
I hope you can check if this is a bug need to be fixed. Thanks a lot.

### Additional contract requirements

- Provide a public function `Bump::try_with_capacity(capacity: usize) -> Result<Bump, AllocErr>` in the `bumpalo` crate.
- When `capacity` cannot be represented as a valid `Layout` (for example, when it exceeds `isize::MAX`), `Bump::try_with_capacity` returns `Err(AllocErr)` instead of panicking.
- When `capacity` is representable, `Bump::try_with_capacity` returns `Ok(Bump)`.
