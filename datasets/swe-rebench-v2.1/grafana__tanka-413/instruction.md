Confirmation prompt not working on Windows
Here's an example (running from Windows Powershell)

```
>tk apply environments/default
Applying to namespace <REDACTED>
Please type 'yes' to confirm: yes
aborted by user
```

Notice that when I type "yes", `tk` replies with "aborted by user".

A (temporary) workaround is to add the `--dangerous-auto-approve` flag. (I like the name, by the way!)

### Additional contract requirements

- Package `term` (import path `github.com/grafana/tanka/pkg/term`) exposes a sentinel error `ErrConfirmationFailed`, returned when the user does not enter the expected approval text.
- Package `term` exposes `Confirm(msg, approval string) error`. It prompts the user, reads a single line of input, and returns `nil` only when the entered line equals `approval`. A line terminated with `\r\n` (Windows) must be accepted exactly like one terminated with `\n`; a mismatch returns `ErrConfirmationFailed`.
- Package `term` exposes `confirmFrom(r io.Reader, w io.Writer, msg string, approval string) error`. It writes the prompt to `w`, reads a single line from `r`, and returns `nil` only when the entered line equals `approval`. It returns `ErrConfirmationFailed` on a mismatch, and a non-nil error when reading from `r` or writing to `w` fails.
- The prompt written to `w` is `msg`, then a newline, then `Please type '<approval>' to confirm: ` with no trailing newline.
