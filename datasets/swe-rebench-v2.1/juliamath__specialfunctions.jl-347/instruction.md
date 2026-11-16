Gamma with Complex{BigFloat} throws StackOverflowError:
Example:
`gamma(big(5.0+1im))`

gives
```
StackOverflowError:

Stacktrace:
 [1] loggamma(::Complex{BigFloat}) at /home/.julia/packages/SpecialFunctions/LC8dm/src/gamma.jl:669 (repeats 79984 times)
```

### Additional contract requirements

- Calling `gamma` or `loggamma` on a `Complex{BigFloat}` argument must not exhaust the stack. It must either return a value or raise an ordinary Julia error.
