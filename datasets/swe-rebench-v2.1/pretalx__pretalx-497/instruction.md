control characters in submissions cause invalid schedule XML
## Expected Behavior

The schedule XML should be valid, regardless of what speakers insert into their submission summary.

## Current Behavior

Inserting control characters (e.g. BEL 0x07, form feed / page break 0x0C) in a submission summary, breaks the resulting schedule XML (according the chrome/giggity).

> This page contains the following errors:
> error on line 555 at column 1: PCDATA invalid Char value 12

## Steps to Reproduce

1. get a control character: `echo -ne "\a" > /tmp/controlchar`
2. get it into your clipboard somehow
3. create a new submission, add character to summary
4. export schedule XML
5. open in chrome/firefox/giggity and receive error

## Context

A speaker copy pasted text from a rich text editor into summary. Page break in the content caused the described failure.

## Your Environment

* Version: v0.7.1
* Environment name and version (e.g. Chrome 39, python 3.5): python 3.6.6
* Operating System and version (desktop or mobile): N/A
* Link to your instance, if in production: N/A, fixed by removing the character

### Additional contract requirements

- Add a public function `xmlescape(text)` in the module `pretalx.common.templatetags.xmlescape`. It accepts any value, converts it to a string, and returns a `django.utils.safestring.SafeString`.
- `xmlescape` removes ASCII control characters 0-8 and 11-31 from its input.
- `xmlescape` escapes `<`, `>`, and `&` as `&lt;`, `&gt;`, and `&amp;`, replaces `"` with `&quot;` and `'` with `&apos;`, and converts non-ASCII characters to numeric character references (for example `ä` becomes `&#228;`).
