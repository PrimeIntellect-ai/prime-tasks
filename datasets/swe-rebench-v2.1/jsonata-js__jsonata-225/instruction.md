$substring length parameter no longer works with negative start positions
I've just noticed that the `$substring()` function isn't handling its length argument correctly when the start argument is negative. For example, this expression correctly evaluates to `"world"`:

```
$substring("Hello world", -5, 5)
```

But so do all of these expressions:

```
$substring("Hello world", -5, 4)    // should return "worl"

$substring("Hello world", -5, 3)    // should return "wor"

$substring("Hello world", -5, 2)    // should return "wo"

$substring("Hello world", -5, 1)    // should return "w"

$substring("Hello world", -5, 0)    // should return ""

$substring("Hello world", -5, -1)   // should return ""
```

I'm guessing that this bug was introduced in the recent fix for [UTF-16 surrogate pairs](https://github.com/jsonata-js/jsonata/issues/156).
