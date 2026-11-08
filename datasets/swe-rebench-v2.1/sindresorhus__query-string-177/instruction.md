Query param ordering is changed on .parse
For example this:
```
?all=monkeys&-all=frank&make=canon&page=1&resultSize=20
```
becomes this:
```
{-all: "frank", all: "monkeys", make: "canon", page: "1", resultSize: "20"}
```

Expected behaviour is that it would produce this:
```
{all: "monkeys", -all: "frank", make: "canon", page: "1", resultSize: "20"}
```

It looks as though it's being sorted on purpose:
https://github.com/sindresorhus/query-string/blob/master/index.js#L205

I noticed that you have an option to disable sorting on `stringify`. Is it possible to have the same option on `parse`?
