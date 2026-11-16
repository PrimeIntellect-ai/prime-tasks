Cannot encode ABI string with non-ASCII characters
## Problem

When I try to encode the value `"What’s your favorite tall building?"` as an ABI `string`, an error occurs.

However, `"What's your favorite tall building?"` works fine. Note the difference between `’` and `'` -- the first is not an ASCII character, while the second is, which leads me to believe non-ASCII characters are not supported.
