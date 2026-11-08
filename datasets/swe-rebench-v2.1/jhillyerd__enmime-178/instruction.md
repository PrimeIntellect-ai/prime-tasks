Attachment having semicolon (;) in filenames are not downloading propery.
What I did: attach a file having name like abc;xyz.doc, test;file.txt

What I expected: File should be properly downloaded with complete name.

What I got: File names are coming partially, it is getting broken  at semicolon (;). So I am only getting file-names as abc, test etc. Also extension is not coming. So files are not opening.

Release or branch I am using: version->v0.8.2, commit id->2a0b399

(Please attach a sample message if you feel it will help reproduce the issue)

### Additional contract requirements

When a MIME attachment has a filename containing a semicolon, parsing the message must preserve the complete filename, including the part after the semicolon and its extension, in the attachment returned to the caller.
