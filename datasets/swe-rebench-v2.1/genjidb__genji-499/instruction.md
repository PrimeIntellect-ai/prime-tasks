Scanning results inside iteration (Result.Iterate, document.ScanIterator) is completely broken
### What version of Genji are you using?
Genji v0.15.1

### What did you do?
Scanning documents during iteration (either inside Result.Iterate manually, or using document.ScanIterator) results in invalid, "broken" documents after the iteration is finished. That is, during iteration, the results are valid, however, after the scan is complete, the scanned items are completely broken. Well, at least the strings, that is, since it seems like they are directly converted from some underlying []byte slice, which is why their content changes after the scan.

Here's an example of the bug on the latest version:
https://go.dev/play/p/qRKyf_jRqlR

### What did you expect to see?

Expected the value during iteration and after iteration to be equal to `main.item{A:2, B:"sample text 2"}`.

### What did you see instead?

During iteration the value is, indeed, scanned correctly as `main.item{A:2, B:"sample text 2"}`. After iteration, however, its contents change to `main.item{A:2, B:"sample text 1"}`.
