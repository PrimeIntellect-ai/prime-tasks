`salmon.encoding.MailBase.keys` doesn't return normalised header names
`MailBase.keys` should return the normalised header names. The raw header names will still be available from `MailBase.mime_part.keys`.

When we refactored how `MailBase` parsed data from the initial email object, we missed the `keys` method - previously there was no way for the header names *not* be normalised already.
