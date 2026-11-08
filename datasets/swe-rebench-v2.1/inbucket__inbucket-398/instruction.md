Inline Attachments not displayed
Reported to the wrong project. Details at jhillyerd/enmime#287

Summary: Inbucket ignores `Content-Disposition: inline` attachments

### Additional contract requirements

- When inline and ordinary attachments are both present, list inline attachments first in the REST `attachments` array, followed by ordinary attachments (for example, `statement.pdf` before `favicon.png`).
