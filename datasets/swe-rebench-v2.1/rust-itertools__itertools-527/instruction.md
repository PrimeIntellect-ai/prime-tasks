flatten_ok
## Proposal

I propose adding the following (without the `impl Iterator`, just to demonstrate):

```rust
    fn flatten_ok<A, B, E>(self) -> impl Iterator<Item=Result<B, E>>
        where Self: Iterator<Item = Result<A, E>>, A: IntoIterator<Item = B>
    {...}
```

`flatten_ok` operates on an iterator of `Result<A, E>` where `A: IntoIterator<Item = B>`. If the iterator produces `Ok`, the value is flattened. If the iterator produces `Err`, the value is produced exactly as-is.

## Why add this?

Several others have been trying to solve this exact problem:
* https://paulkernfeld.com/2018/11/03/flatten-nested-iterator-result.html
* https://stackoverflow.com/questions/59852161/how-to-handle-result-in-flat-map

I also encountered this problem and was unable to find a combinator for this purpose, which was surprising to me.

## Potential way to implement

It could be implemented this way:
```rust
fn flatten_ok<A, B, E>(self) -> impl Iterator<Item=Result<B, E>>
where Self: Iterator<Item = Result<A, E>>, A: IntoIterator<Item = B>
{
[HIDDEN]
}
```

Of course, a struct could be created within `itertools` to implement the `Iterator` so there is no external API dependency on `either`, and so we can still specify a concrete return type, but the above would approximately the implementation used and does work if this signature (with `impl Iterator`) is acceptable.

## Questions

* Is there another and more clear way to implement this that others are missing? If so, please let me know.
* Should this be proposed to `libcore` first?
