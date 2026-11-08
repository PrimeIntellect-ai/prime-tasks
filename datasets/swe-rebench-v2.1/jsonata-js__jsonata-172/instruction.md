$formatNumber always pads numbers with '0'
The formatNumber function sometimes needs to pad numbers with zeroes. For example, this expression:

    $formatNumber(2, "000.000")

returns the number 2 padded to 3 digits before and after the decimal place:

    "002.000"

If I provide a custom zero digit, I'd expect formatNumber to use it for the padding. But this expression:

    $formatNumber(2, "AAA.AAA", {"zero-digit": "A"})

produces this:

    "00C.000"

As you might expect, the '2' is now a 'C' but it's padded with '0' instead of the zero digit specified (I used the letter 'A' but the outcome is the same whatever character you choose*).

The same applies to exponents that need padding, e.g.

    $formatNumber(0.1, "AeAAA", {"zero-digit": "A"})

returns:

    "Be-00B"

[*] When I was trying out these examples, I noticed that formatNumber doesn't handle non-BMP zero digit characters such as '𝟶' (U+1D7F6). I suspect this is related to [issue 156](https://github.com/jsonata-js/jsonata/issues/156) but I haven't investigated further.
