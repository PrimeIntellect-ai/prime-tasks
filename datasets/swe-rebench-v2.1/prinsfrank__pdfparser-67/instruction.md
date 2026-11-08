Missing support for multiple codespaceranges (Unrecognized codespacerange format)
```
begincodespacerange
<0003> <005a>
<0102> <01b5>
<0357> <03ed>
endcodespacerange
```

results in
PrinsFrank\PdfParser\Exception\ParseFailureException: Unrecognized codespacerange format
For reproduction, see the file from https://github.com/k00ni/pdfparser/commit/3c1372ca36b2de666e3af752ec85dd69a27a445a on the latest commit in main.
