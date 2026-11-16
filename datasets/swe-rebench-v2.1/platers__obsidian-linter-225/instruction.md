Timestamp improvement
I have linting set to auto-lint on save.

As a habit, I always lint files, even if I did not modify. The issue is if there was no linting issue (the file was not changed), the modified date is updated regardless, even if nothing was actually modified.

It gets worse when I lint all files, because all files will have their modified timestamps changed. This is an issue esp when using version control, because this will modify all files all the time.

NB: I don't think anyone would want to change the timestamps of an unchanged file, so maybe it would be better to just add this improvement without a settings checkbox. Should be a minor version change.

### Additional contract requirements

When a lint run changes a file's contents, update its modified-date field using the file's modified timestamp. This includes changes made by other lint rules and changes made while adding timestamp fields.
