output-template from CLI considers \n as literal and not line break
<!--
Thank you for helping to improve terraform-docs!

Please be sure to search for open issues before raising a new one. We use issues
for bug reports and feature requests. Please note, this template is for bugs
report, not feature requests. For more information, see the Contributing Guidelines
at https://git.io/JtEzg. Please find us at https://slack.terraform-docs.io/ for
questions, support, and discussion.
-->

### Describe the bug

<!--
Please let us know what behaviour you expected and how terraform-docs diverged
from that behaviour.
-->

When passing `--output-template` as CLI flag, `\n` is not processed as line break rather than literal strings. As such there's the following, misleading, error: `value of '--output-template' should contain at least 3 lines (begin comment, {{ .Content }}, and end comment)`

### How can we reproduce it?

<!--
Help us to reproduce your bug as succinctly and precisely as possible. Any and
all steps or script that triggers the issue are highly appreciated!

Do you have long logs to share? Please go to https://ghostbin.com and insert the
link here.
-->

```bash
$ terraform-docs markdown table --output-file README.md --output-template '<!-- BEGIN -->\n{{ .Content }}\n<!-- END -->'
Error: value of '--output-template' should contain at least 3 lines (begin comment, {{ .Content }}, and end comment)
exit status 1
```
