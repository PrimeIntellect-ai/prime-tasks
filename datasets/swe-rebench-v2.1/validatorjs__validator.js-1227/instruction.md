isDivisibleBy string comparison inconsistent
The function is `->isDivisibleBy` will use the first number in a string to do the comparison, even if the string is not a valid number. This is problematic when passing a date string in because `2020-01-01T00:15:38.184Z`  / `2` will pass but `2019-01-01T00:15:38.184Z` will not.

**Actual Results:**

```js
const validator = require('validator');
validator.isDivisibleBy('2020-a', 2); // true
validator.isDivisibleBy('2019-a.', 2); // false
validator.isDivisibleBy('2#bar', 2); // true
validator.isDivisibleBy('1#foo', 2); // false
```

**Expected Result:**

```js
const validator = require('validator');
validator.isDivisibleBy('2020-a', 2); // false
validator.isDivisibleBy('2019-a.', 2); // false
validator.isDivisibleBy('2#bar', 2); // false
validator.isDivisibleBy('1#foo', 2); // false
```
