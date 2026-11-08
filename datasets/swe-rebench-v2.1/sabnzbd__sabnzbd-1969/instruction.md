[Request] Restore UUEDECODE Support
I've run into a few binary posts in various groups that still use UUENCODING so it would be nice if there was _optional_ uudecode support in SABNZBd.

(Ran into one as recently as Oct 20 2020).

### Additional contract requirements

- Add a public function `decode_uu(article, raw_data)` in the module `sabnzbd.decoder`. It returns the decoded binary payload as `bytes`.
- `raw_data` is a list of `bytes` chunks as read from the NNTP socket; each chunk may contain several lines separated by `\r\n`, and the article may be split across the list elements.
- `decode_uu` locates the payload after optional NNTP response/header lines separated from the body by an empty line, or directly after the NNTP response line.
- Add a public exception class `BadUu` in `sabnzbd.decoder` that can be constructed without arguments. It is raised when the data is missing, too short, or does not contain a valid `begin` line.
- Add a public exception class `BadData` in `sabnzbd.decoder` whose `data` attribute holds the bytes that were successfully decoded before the failure. It is raised when a line cannot be decoded.
- For the first part of a file, `decode_uu` records the file's type as `"uu"`, stores the MD5 checksum of the first 16384 decoded bytes in the file's `md5of16k`, and verifies the file's name by calling `verify_nzf_filename` on the download object (`nzo`) with the name from the `begin` line.
