Day 61
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Implement integer exponentiation. That is, implement the pow(x, y) function, where x and y are integers and returns x^y.

Do this faster than the naive method of repeated multiplication.

For example, pow(2, 10) should return 1024.

### Additional contract requirements

In the `day61` Go package, expose `IntegerExponentiationBySquaring(x, y uint) uint`. It must return x raised to the power y and handle large exponents substantially faster than performing one multiplication per exponent step.
