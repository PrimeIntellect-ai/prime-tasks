[Bug]: Fix string content from dictionary values when hex/unicode encoded.
### Is there an existing issue for this?

- [x] I have searched the existing issues and found no similar reports

### Are you using the latest version of this package?

- [x] The issue I'm reporting exists in the latest release

### Can other PDF readers read the file?

- [x] The PDF I'm trying to read opens correctly in at least one other PDF reader

### When running this snippet

```PHP
$document = PdfParser::parse(Stream::openFile('/path/to/file.pdf'));
$document->getTitle();
```

### I run into the following issue/exception (Please attach the pdf)

Some dictionary textStringValues are still hex-encoded, like `<0000>`

### Do you allow attachment files to be used in tests to prevent regressions?

- [ ] Yes, I give permission to use this file as a test file to prevent future regressions (And am authorized to give this permission)
