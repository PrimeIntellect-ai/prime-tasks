gitdiff: line 63: git file header: invalid mode line: invalid syntax
Looks like your library is a bit out-of-date? Line 63 for me in sample I was testing with looks like this:

```
new file mode 100644
```

### Additional contract requirements

A Git file header mode line (for example `new file mode 100644`) may be terminated with a CRLF line ending, so the line passed to the parser can end with a trailing carriage return. Such a mode line must be parsed successfully instead of being rejected as an invalid mode line.
