parseExpression() loses ? information
Thank you for producing this very useful library. I think this is a bug, but I am happy to be corrected.

I have a cron expression with a question mark in it:
`0 0 17 * * ?`

No problems parsing it, but if I stringify it without making any changes, I expect to get the same cron. But instead the `?` is converted to a `*` and it becomes:
`0 0 17 * * *`

````js
const result = parseExpression("0 0 17 * * ?");
console.log(result.stringify(true));  // prints "0 0 17 * * *"
````

How can I parse such an expression, and stringify it later to get back the original specification?
