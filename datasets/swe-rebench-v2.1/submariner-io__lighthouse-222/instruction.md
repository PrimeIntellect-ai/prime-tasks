Append to the ServiceExportCondition list
When we update the `ServiceExport` status, we always overwrite the entire in the `ServiceExportCondition`. Since it's a list, we should append if the new `ServiceExportCondition` is different than the previous entry. Also we probably want to truncate the list to keep the last 10 or so entries.

### Additional contract requirements

- The `ServiceExportCondition` list retains at most 10 entries by default. When appending a new condition would exceed this limit, the oldest entry is dropped so that the list length stays at 10.
