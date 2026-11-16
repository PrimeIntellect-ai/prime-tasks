StringConcatenationCheck : Ignore string concatenations composed entirely of literals
This :
```
let x = "<blah><blah><blah>" +
"<blah><blah><blah>" +
"<blah><blah><blah>" +
"<blah><blah><blah>"
```
should not result in RSPEC-3512 being raised. There are only literals here and using a template makes no sense.
