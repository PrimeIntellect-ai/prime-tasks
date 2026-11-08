attachments - Support for InputStream?
In version 3, any plans to update attachments to support InputStream instead of File?  Our system creates PDF on the fly, never saving to file system.  Works in your version 2...need this to upgrade.

Thanks!

### Additional contract requirements

Callers can provide attachment data with an `InputStream` using `Attachments.Builder(String fileName, InputStream content)`, without first saving the data to a file. Building the attachment exposes its content as the Base64 encoding of the bytes read from the stream.
