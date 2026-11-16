obs-fold is implemented incorrectly
The HTTP RFCs specify that when an HTTP/1.1 implementation receives a header line that begins with a space or horizontal tab, it has two choices:
1. Reject the request
2. Concatenate (fold) this line into the previous header line.

Tornado implements this incorrectly. In addition to folding header lines beginning with spaces and tabs, Tornado also folds header lines beginning with any of the following bytes:
- 0x0b
- 0x0c
- 0x0d
- 0x1c
- 0x1d
- 0x1e
- 0x1f
- 0x85
- 0xa0

### Additional contract requirements

- Rejecting a header line is signaled by raising `tornado.httputil.HTTPInputError`.
- A header line that begins with a space or horizontal tab and has no previous
  header line to continue (for example the first line of the header block) must
  be rejected.
