deep.equal() and deep.include() doesn't work with Error
`deep.equal()` and `deep.include()` doesn't compare the object keys as I expect it to. I found the issue when upgrading to v4 as the `deep.equal()` works fine in v3.5. It stopped working in v4+.

Here is a code to confirm the issue: https://jsfiddle.net/wLzrucae/3/.

I tried adding `error` to the allowed types for `include()` assertion, but it still failed on comparison. Any ideas?

### Additional contract requirements

- `.include()` and `.deep.include()` must accept an `Error` object as the target and compare the requested keys (for example `message`) as expected.
- `.include()` must also accept an ordinary object that carries a custom `Symbol.toStringTag` (`@@toStringTag`) and compare the requested keys as expected.
- Deep equality must consider an Error equal to itself and must consider two Error objects with different `message` values unequal.
