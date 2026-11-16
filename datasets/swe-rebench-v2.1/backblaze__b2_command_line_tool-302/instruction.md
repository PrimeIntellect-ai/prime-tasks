Set `src_last_modified_millis` in `b2 upload_file`
When you use `sync` to upload files, it always sets `src_last_modified_millis`.  But uploading single files doesn't, which can cause later syncs to get confused.

I propose that `src_last_modified_millis` be set for every uploaded file.  If the user doesn't specify a value on the command line, we can take it from the file.

It would be good to check and make sure that the local clock isn't too different from the server's clock before uploading anything.

### Additional contract requirements

When `src_last_modified_millis` is supplied through `b2 upload_file` file info, the uploaded file must retain that value; it must not be replaced with the local file's modification time.

The clock-check sentence above is a suggestion, not a required behavior of this change. Upload behavior is not required to check or react to differences between the local and server clocks.
