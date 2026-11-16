[Feature request] Set User-agent
**Is your feature request related to a problem? Please describe.**
The original problem is #144, which is some host denies accessing from urllib.

**Describe the solution you'd like**
Set User-agent when localizing a file.

**Describe alternatives you've considered**
Download a PDF manually.

**Additional context**
Nothing.

### Additional contract requirements

- `tabula.read_pdf` accepts an optional `user_agent` keyword argument. When the input is a remote URL, the supplied value is passed to the file-localization step so that the download uses it as the HTTP User-Agent header.
- `tabula.file_util.localize_file(path_or_buffer, user_agent=None)` accepts an optional `user_agent`. When the input is a remote URL and a `user_agent` is supplied, the download request is made with that value as the HTTP User-Agent header.
