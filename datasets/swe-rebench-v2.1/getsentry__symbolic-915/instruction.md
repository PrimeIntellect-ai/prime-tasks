Symcaches created from WASM files with symbol tables only contain 1 function
Zendesk: https://sentry.zendesk.com/agent/tickets/149793

Converting the mentioned WASM files to SymCaches produces something like
```
Cache info:
SymCache {
    version: 8,
    debug_id: DebugId {
        uuid: "1031808b-46af-1a4c-83a4-cc79b80638b1",
        appendix: 0,
    },
    arch: Wasm32,
    files: 0,
    functions: 1,
    source_locations: 109745,
    ranges: 109745,
    string_bytes: 44203617,
}
```
despite there being lots of symbols in the symbol table.

### Additional contract requirements

The defect is not limited to WASM files. For any object file, an entry from the
symbol table must be inserted into the resulting SymCache even when its address
coincides with the end of a function (an address that would otherwise be
unmapped). Looking up such an address in the SymCache must return the
symbol-table function (and only that function), exposing the symbol's name and
its entry address, rather than an empty result.
