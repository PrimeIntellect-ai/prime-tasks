Write key value metadata after rows
I see how to use the `KeyValueMetadata` function to configure a writer when constructing that writer.  This is useful if the key value metadata is known ahead of writing the rows.  I'm hoping to find a way to write key value metadata after writing rows.  In my case, the key value metadata includes summary information about the rows.  I'm trying to write the parquet file in a streaming manner and wanted to avoid buffering all rows to create the key value metadata summary.

I tried using `NewWriterConfig`, creating a reader with `NewGenericReader`, and then modifying the `config.KeyValueMetadata` after writing rows.  However, `NewGenericReader` creates a new config internally, so the one I am able to modify is no longer used.

Is there a way to add key value metadata after writing rows and before writing the file footer?

### Additional contract requirements

Provide `SetKeyValueMetadata(key, value string)` on both `Writer` and `GenericWriter[T]`. Callers can invoke it after writing rows and before closing the writer; the supplied key/value pair must appear in the resulting file footer metadata.
