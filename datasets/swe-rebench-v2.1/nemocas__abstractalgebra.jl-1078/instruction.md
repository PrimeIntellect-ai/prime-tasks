Poly sqrt test failure
The following very rare issue seems to occur randomly.

```
julia> S, x = PolynomialRing(QQ, "x")
(Univariate Polynomial Ring in x over Rationals, x)

julia> f = x^2 + x + 1//4
x^2 + x + 1//4

julia> issquare_with_sqrt(f)
(true, x + 1//2)

julia> issquare(f)
false

julia> issquare_with_sqrt(f)
(false, 0)
```

The following may be related, but I only seem to be able to trigger it for longer polynomials (length >= 20)

```
julia> S, x = PolynomialRing(QQ, "x")
(Univariate Polynomial Ring in x over Rationals, x)

julia> f = -1//8*x^17 - 11//16*x^16 + 1//2*x^15 - 1//3*x^14 + 4//3*x^13 + 3//5*x^12 + 5//4*x^11 - 7//15*x^10 + 1//5*x^9 + 1//4*x^8 + 1//3*x^7 - 2*x^6 + 8//3*x^5 + 14*x^4 - x^2 + 9//2*x - 2//7
-1//8*x^17 - 11//16*x^16 + 1//2*x^15 - 1//3*x^14 + 4//3*x^13 + 3//5*x^12 + 5//4*x^11 - 7//15*x^10 + 1//5*x^9 + 1//4*x^8 + 1//3*x^7 - 2*x^6 + 8//3*x^5 + 14*x^4 - x^2 + 9//2*x - 2//7

julia> issquare(f^2)
false
```
