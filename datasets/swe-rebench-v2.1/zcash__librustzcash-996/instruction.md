zcash_client_backend: Return scan summary from `scan_cached_blocks`
It is useful for the wallet to be able to skip updating the UI when scanning a range of blocks results in no changes to wallet state. The easiest way to do this is for `scan_cached_blocks` to report this to the caller so that the caller can choose whether to update the UI.

### Additional contract requirements

- `zcash_client_backend::data_api::chain::scan_cached_blocks` returns a `ScanSummary` on success, in addition to its existing error type.
- `ScanSummary` is a public type defined in the `zcash_client_backend::data_api::chain` module.
- `ScanSummary::scanned_range(&self) -> Range<BlockHeight>` returns the range of block heights actually scanned.
- `ScanSummary::received_sapling_note_count(&self) -> usize` returns the number of notes belonging to the wallet that were received in the scanned range.
- `ScanSummary::spent_sapling_note_count(&self) -> usize` returns the number of previously detected wallet-owned Sapling notes spent in the scanned range. This lets a caller distinguish a scan that spends a note, even without receiving a note, from one that makes no wallet-state change.
