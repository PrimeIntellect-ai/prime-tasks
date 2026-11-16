MPolyBuildCtx's finish does not restart the poly
Instead of acting like an assembly line that can be used to create a bunch of MPoly's, `finish` just gives you a current snapshot of all building that has taken place. It is therefore useless for creating multiple polynomials. The current behavior is (and this cannot be maintained efficiently for singular polynomials):
```R, (x, y) = QQ["x", "y"]; B = MPolyBuildCtx(R);
julia> R, (x, y) = QQ["x", "y"]; B = MPolyBuildCtx(R);
julia> push_term!(B, QQ(6), [6, 6]); finish(B)
6*x^6*y^6
julia> push_term!(B, QQ(5), [5, 5]); finish(B)
6*x^6*y^6 + 5*x^5*y^5
julia> push_term!(B, QQ(4), [4, 4]); finish(B)
6*x^6*y^6 + 5*x^5*y^5 + 4*x^4*y^4
```
and I propose
```R, (x, y) = QQ["x", "y"]; B = MPolyBuildCtx(R);
julia> R, (x, y) = QQ["x", "y"]; B = MPolyBuildCtx(R);
julia> push_term!(B, QQ(6), [6, 6]); finish(B)
6*x^6*y^6
julia> push_term!(B, QQ(5), [5, 5]); finish(B)
5*x^5*y^5
julia> push_term!(B, QQ(4), [4, 4]); finish(B)
4*x^4*y^4
```
