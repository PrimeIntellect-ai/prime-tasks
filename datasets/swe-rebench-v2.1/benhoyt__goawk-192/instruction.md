Parser doesn't allow null ; (semicolon)
GoAWK fails with a parse error on `{}` blocks with just semicolons in them (other AWKs support that, so presumably it's allowed by the grammar). For example:

```
$ goawk 'BEGIN {;}'
<cmdline>:1:9: expected expression instead of }
BEGIN {;}
        ^
$ goawk 'BEGIN { while (0) {;;} }'
<cmdline>:1:22: expected expression instead of }
BEGIN { while (0) {;;} }
                     ^
```

Thanks @raygard for the bug report.
