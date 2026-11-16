parse_options_header quote handling
I wrote a new version of cgi.parse_header / werkzeug.parse_options_header with better handling for various special cases that unfortunately occur. The new implementation is also twice faster than the two others.

````python
import re
import typing

Options = typing.Dict[str, str]  # key=value fields in various headers

[HIDDEN]
````

This does not support werkzeug.parse_options_header's multiple=True, which I didn't see being used anywhere anyway (is that for accept-header or what?). This is written for Sanic, but if anyone cares to port it to Werkzeug, the code is there (sorry -- don't have time to do it myself). Adding support for multiple=True is a few lines of code (with proper handling of quoted commas), if deemed useful.

CPython cgi.parse_header tests as well as two others that I added based on testing real browsers all pass with this:

````python
import pytest

from sanic import headers


@pytest.mark.parametrize(
    "input, expected",
    [
        ("text/plain", ("text/plain", {})),
        ("text/vnd.just.made.this.up ; ", ("text/vnd.just.made.this.up", {})),
        ("text/plain;charset=us-ascii", ("text/plain", {"charset": "us-ascii"})),
        ('text/plain ; charset="us-ascii"', ("text/plain", {"charset": "us-ascii"})),
        (
            'text/plain ; charset="us-ascii"; another=opt',
            ("text/plain", {"charset": "us-ascii", "another": "opt"})
        ),
        (
            'attachment; filename="silly.txt"',
            ("attachment", {"filename": "silly.txt"})
        ),
        (
            'attachment; filename="strange;name"',
            ("attachment", {"filename": "strange;name"})
        ),
        (
            'attachment; filename="strange;name";size=123;',
            ("attachment", {"filename": "strange;name", "size": "123"})
        ),
        (
            'form-data; name="files"; filename="fo\\"o;bar\\"',
            ('form-data', {'name': 'files', 'filename': 'fo"o;bar\\'})
            # cgi.parse_header:
            # ('form-data', {'name': 'files', 'filename': 'fo"o;bar\\'})
            # werkzeug.parse_options_header:
            # ('form-data', {'name': 'files', 'filename': '"fo\\"o', 'bar\\"': None})
        ),
        # <input type=file name="foo&quot;;bar\"> with Unicode filename!
        (
            # Chrome:
            # Content-Disposition: form-data; name="foo%22;bar\"; filename="😀"
            'form-data; name="foo%22;bar\\"; filename="😀"',
            ('form-data', {'name': 'foo";bar\\', 'filename': '😀'})
            # cgi: ('form-data', {'name': 'foo%22;bar"; filename="😀'})
            # werkzeug: ('form-data', {'name': 'foo%22;bar"; filename='})
        ),
        (
            # Firefox:
            # Content-Disposition: form-data; name="foo\";bar\"; filename="😀"
            'form-data; name="foo\\";bar\\"; filename="😀"',
            ('form-data', {'name': 'foo";bar\\', 'filename': '😀'})
            # cgi: ('form-data', {'name': 'foo";bar"; filename="😀'})
            # werkzeug: ('form-data', {'name': 'foo";bar"; filename='})
        ),
    ]
)
def test_parse_headers(input, expected):
    assert headers.parse_content_header(input) == expected
````

### Additional contract requirements

The parser must return the primary header value trimmed while preserving its capitalization, and option names lowercased. It must preserve the empty primary value when the input contains no primary value.

Quoted option values must retain embedded semicolons and interpret browser-style escaped quotes, including backslash-escaped quotes and `%22`. Malformed option parts that do not provide a valid key and value are ignored.

RFC 2231 extended parameters and indexed continuations must continue to work, including decoding UTF-8 percent-encoded values and assembling continuation parts.
