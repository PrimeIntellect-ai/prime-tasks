`<@1>` parsed as inline link
Events from pulldown-cmark:

```rust
"<@1>" -> [
  Start(Paragraph)
    Start(Link { link_type: Inline, dest_url: Borrowed("@1"), title: Borrowed(""), id: Borrowed("") })
      Text(Borrowed("@1"))
    End(Link)
  End(Paragraph)
]
```

Events from commonmark.js:

```rust
"<@1>" -> [
  Start(Paragraph)
    Text(Boxed("<@1>"))
  End(Paragraph)
]
```

XML from [commonmark.js](https://spec.commonmark.org/dingus/?text=%3C%401%3E):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE document SYSTEM "CommonMark.dtd">
<document xmlns="http://commonmark.org/xml/1.0">
  <paragraph>
    <text>&lt;</text>
    <text>@1&gt;</text>
  </paragraph>
</document>
```

I looked at the [section on autolinks in the spec](https://spec.commonmark.org/0.30/#autolinks) and the problem seems to be that `scan_email` accepts `@1` as a valid email address. However, the spec says

> An [email address](https://spec.commonmark.org/0.30/#email-address), for these purposes, is anything that matches the [non-normative regex from the HTML5 spec](https://html.spec.whatwg.org/multipage/forms.html#e-mail-state-(type=email)):
>
>     /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
>     (?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

There is a comment at the start of `scan_line` saying that the text is scanned by hand to avoid using a regex library. I suppose we could rewrite the code there to parse the regex more faithfully, or perhaps we could pull in a regex library?

### Additional contract requirements

Recognize an angle-bracket email autolink only when its address matches the quoted HTML5 email-address syntax. An address that does not match must remain ordinary text; in particular, parsing `<@1>` must produce paragraph text rather than an inline link.
