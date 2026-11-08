Support Writing Local Symbol Table Append
Read support was introduced in #98 still missing write support

### Additional contract requirements

- Calling `IonWriter.flush()` must make buffered top-level values available in the output without finalizing the writer or its current local symbol table. The writer must remain usable for subsequent top-level values; symbols encountered later must be appended so earlier values remain readable with their original symbol meanings.
