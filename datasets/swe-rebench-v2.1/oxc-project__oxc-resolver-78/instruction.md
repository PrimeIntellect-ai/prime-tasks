aliased requests in resolver_context.file_dependencies are not normalized/canonicalized
```
oxc_resolver: 1.2.0-1.3.0
os: Windows
```

## Summary


```rs
let root = dir().join("fixtures\\enhanced_resolve\\test\\fixtures");
let mut ctx = ResolveContext::default();

let resolver = Resolver::new(ResolveOptions {
    alias: vec![(
        "@".into(),
        vec![AliasValue::Path(root.join("alias").to_string_lossy().into())],
    )],
    ..ResolveOptions::default()
});
let _ = resolver.resolve_with_context(root, "@/files/a", &mut ctx);

for d in ctx.file_dependencies.iter() {
    println!("{}", d.to_string_lossy());
}
```

### Expected
`C:\Users\imkf\Developer\oxc-resolver\fixtures\enhanced_resolve\test\fixtures\alias\files\a.js` seen in output,

### Actual

`C:\Users\imkf\Developer\oxc-resolver\fixtures\enhanced_resolve\test\fixtures\alias/files/a.js` got

## Related

web-infra-dev/rspack#5445

### Additional contract requirements

When resolving an aliased request with a path suffix, the corresponding path recorded in `ResolveContext.file_dependencies` must use a consistent native path representation, without mixed or redundant separators.
