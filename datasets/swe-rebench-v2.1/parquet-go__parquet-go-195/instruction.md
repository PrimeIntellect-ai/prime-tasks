Optimistically reading file footer breaks Tempo caching logic
I like [this recent PR](https://github.com/parquet-go/parquet-go/pull/192) and believe it will help in the general case, but Tempo has logic to [immediately return the footer length and cache the footer](https://github.com/grafana/tempo/blob/e61733554c09fb59d6990eff48dc9c511b5c22cf/tempodb/encoding/vparquet4/readers.go#L98-L114) in an off process cache. This PR breaks that behavior by changing the ranges it attempts to read.

Are we good on a PR to make this new behavior configurable? I'd be glad to submit it.

### Additional contract requirements

Callers can choose whether opening a Parquet file uses the newer optimistic footer read. The `parquet.OptimisticRead(enabled bool)` file option, passed to `parquet.OpenFile`, enables the larger footer read when `enabled` is true. When `enabled` is false, the EOF-ending footer read must remain smaller than the read made with optimistic reading enabled; its exact byte length is not otherwise fixed.
