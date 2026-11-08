Document expected structure of Jsonnet output
Hi team,

We're trying out tanka for managing our core kubernetes cluster configuration but have hit a few roadbumps.

Most of our problems appear to stem from lack of understanding about what type of object tanka is expecting your jsonnet to generate from the environments file.

From looking at your examples, it appears the implicit expectation is that tanka will recursively descend your jsonnet structure, assuming that your structure is a tree with kubernetes object leaf nodes. So that assumes that you have one global object which is a map of string to object, where that object is either a kubernetes resource or another tree.

```haskell
data Resource = Resource {
  apiVersion :: String, kind :: String, metadata :: Metadata
}
data Environment = Resource || [(string, Environment)]
```

If this is so, it would be great to document it. I suspect we might be missing something though, as tanka panics when we construct several otherwise valid configs, such as:

```
{
  a: {
    apiVersion: 'v1',
    kind: 'List',
    items: [/* valid k8s resources */],
  },
  b: self.a,
}
```

Lacking a clear explanation about what this format is makes it difficult to adopt tanka as a tool. All the advertising says tanka is a great `function`, but we don't know what the type signature is.

Can you help us out? Cheers.

### Additional contract requirements

- The expected structure of the Jsonnet output must be documented in the repository at `docs/jsonnet/expected-structure.md`.
- That documentation must state that Tanka identifies a Kubernetes object by the presence of both `apiVersion` and `kind`, and must describe the supported shapes of Jsonnet output, including nested objects and arrays, as well as the `kubectl` `List` pseudo-type.
