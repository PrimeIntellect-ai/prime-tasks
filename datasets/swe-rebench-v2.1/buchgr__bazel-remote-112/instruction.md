Prune empty actions
We have a case where some empty actions managed to sneak into our `ac` cache.

```
$ find ac -size 0 | head
ac/0a/0a372b8f6f57e408155b2d77291599fa69c3ad44c32a370579bc3fd582f462e6
ac/1d/1d16b14f8365aa77a51617086c6a6675fd216480223ffa02a5cbf33322570f8d
ac/87/875ac9c5592f5f8c86dc05d3c61d18a9d7aac85c0930b7b36290ba9f46fa3367
```

These are problematic because Bazel will fail the build when the outputs are not created.

Would it make sense for `bazel-remote` to refuse to serve empty actions?

### Additional contract requirements

Reject Action Cache uploads whose serialized ActionResult payload is zero bytes. This applies to both gRPC and HTTP uploads and the empty payload must not be admitted to the cache. This upload requirement does not change how already-cached entries are served.
