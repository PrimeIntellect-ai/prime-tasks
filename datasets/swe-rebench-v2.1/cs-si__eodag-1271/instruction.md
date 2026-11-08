rename camelCase parameters and methods
Rename:
[HIDDEN]
- `orderDownload` to `order_download`
- `orderDownloadStatus` to `order_download_status`

### Additional contract requirements

- Rename `sortBy` to `sort_by` as the search argument exposed by `EODataAccessGateway.search`, represented by `SearchArgs`, and produced by the EODAG search conversion (`EODAGSearch`).
- Each entry of the `sort_by` list must be a two-item tuple; an entry that is not a two-item tuple is rejected.
