"repeated argument not allowed here" false negative parse error
```
/home/geirsson/frontend/common/app/views/support/package.scala:87: error: repeated argument not allowed here
def withJsoup(html: Html)(cleaners: HtmlCleaner*): Html = withJsoup(html.body) { cleaners: _* }
                                                                                             ^
```

Discovered while running scalafix on https://github.com/guardian/frontend

### Additional contract requirements

- The original `withJsoup` example must parse successfully; a braced call whose body consists of a single repeated argument is valid.
- Parsing `foo(bar) { val baz = qux; baz: _* }` must fail with a diagnostic beginning `<input>:1: error: repeated argument not allowed here`.
