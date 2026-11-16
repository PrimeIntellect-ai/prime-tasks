parser: parse expression cannot parse functions
**Describe the bug**
The parser can not follow the function production rule `function-name ( expr )`.

**To Reproduce**
Try to parse `SELECT AVG(price) AS average_price FROM items LEFT INNER JOIN prices`.

**Expected behavior**
`AVG` is clearly a literal, however, it must be stored in `function-name` instead of `literal-value`, because it is followed by an opening parenthesis.
