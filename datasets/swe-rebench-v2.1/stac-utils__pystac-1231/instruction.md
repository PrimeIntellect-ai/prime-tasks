Rework extensions to handle "future" versions correctly
When loading extension data, extension implementations should use [HIDDEN] (or whatever) to detect the presence of the extension, not an exact string match.

### Additional contract requirements

- Extension presence detection must recognize schema URIs for future versions of the same extension, rather than requiring an exact match to a known schema URI.
