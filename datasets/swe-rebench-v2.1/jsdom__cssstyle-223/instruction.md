Negative values invalid for `marginBottom`?
I see [HIDDEN] (and the tests assert that the value cannot be negative) - is this correct?

https://github.com/jsdom/cssstyle/blob/ba349623a94d5d1fc6527c770e6684acc82bac44/lib/properties/marginBottom.js#L6

https://github.com/jsdom/cssstyle/blob/ba349623a94d5d1fc6527c770e6684acc82bac44/lib/parsers.js#L230

https://github.com/jsdom/cssstyle/blob/ba349623a94d5d1fc6527c770e6684acc82bac44/test/properties.test.js#L815-L817

I understood that its value can be positive, zero, or negative (see [https://developer.mozilla.org/en-US/docs/Web/CSS/margin-bottom](https://developer.mozilla.org/en-US/docs/Web/CSS/margin-bottom#:~:text=Its%20value%20can%20be%20positive%2C%20zero%2C%20or%20negative)).

### Additional contract requirements

- `margin-bottom` must accept negative length and percentage values.
