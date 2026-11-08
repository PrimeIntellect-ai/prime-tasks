Failing to deserialize an array of heap-allocated objects may leak memory
Thanks for the serde replacement!

It seems that the use of MaybeUninit in the [DeBin impl for arrays](https://github.com/not-fl3/nanoserde/blob/7d40e5e8092535ce9a4f83cae566db578e2850be/src/serde_bin.rs#L400) can cause a memory leak when array deserialization fails.

Here's an example, where the loop leaks about 4 KiB per iteration:
```
fn main() {
    let items: [Vec<u8>; 2] = [vec![1u8; 4096], vec![1u8; 4096]];
    let serialized = nanoserde::SerBin::serialize_bin(&items);
    let corrupted_serialized = &serialized[..serialized.len() - 1];
    for i in 0..1_000_000 {
        if i % 1000 == 0 {
            dbg!(i);
        }
        let _: Result<[Vec<u8>; 2], _> = nanoserde::DeBin::deserialize_bin(corrupted_serialized);
    }
}
```
