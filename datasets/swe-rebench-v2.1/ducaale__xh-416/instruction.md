filename for utf8 content-disposition is not correct
I use xh --download to download a file.
and the filename is Download.bin.
It should be sql04071104.csv
![Image](https://github.com/user-attachments/assets/e512c2d3-da4e-4b61-9eca-14a5cf253458)

### Additional contract requirements

- With `xh --download`, when a response supplies a UTF-8 filename in its `Content-Disposition` header, save the download using that filename rather than the fallback name `Download.bin`. For the reported case, the filename is `sql04071104.csv`. For a UTF-8 filename supplied in RFC 5987 percent-encoded form, decode the percent escapes before using the filename.
- A supplied filename containing path components must not cause a download to be written outside the download directory.
