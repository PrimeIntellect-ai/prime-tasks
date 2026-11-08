Control row group size
Hello, I haven't found how to control row group size.

Yes, I can call `Flush`, but how do I know if row group reached limit size (1GB for example) ?

### Additional contract requirements

- Provide the public writer option `MaxRowsPerRowGroup(numRows int64) WriterOption`. It limits each row group to the specified number of rows; when the limit is reached, the writer automatically starts a new row group.
