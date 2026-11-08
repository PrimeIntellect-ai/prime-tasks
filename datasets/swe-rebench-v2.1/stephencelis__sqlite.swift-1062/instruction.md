Is there a “VACUUM” function to reduce file size?
I delete a lot of data when adding new one to my database to keep the file size low. But as the deleted rows remain in the memory the file size doesn’t reduce. Is there a supported vacuum function?

### Additional contract requirements

Provide a supported `Connection.vacuum()` method that runs SQLite VACUUM on that connection to reclaim unused database space.
