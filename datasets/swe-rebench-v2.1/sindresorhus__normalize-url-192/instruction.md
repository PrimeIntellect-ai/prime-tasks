Decoding entire pathname leads to edge case issues
The short of it is, if you have `%5C` in your URL string before normalizing it, you will end up with a `/` in the final result instead of a `\`. You can read my much lengthier explanation on [Ghost issue #20484](https://github.com/TryGhost/Ghost/issues/20484#issuecomment-2910906159).

I'll submit a PR shortly.

### Additional contract requirements

- For example, normalizing `https://foo.com/some%5Bthing%5Celse/that-is%40great@coding` must return `https://foo.com/some[thing%5Celse/that-is%40great@coding`.
