Error when changing polynomial degree for `TaylorModel1{TaylorN{T} ,T}`
The following yields an error:
```julia
julia> using TaylorModels;

julia> xN, yN = set_variables("x y", order=4, numvars=2);

julia> xtm1_order5 = exp( TaylorModel1( Taylor1(xN, 5), 0..0, 0..0, -0.5 .. 0.5) )
  1.0 + 1.0 x + 0.5 x² + 0.16666666666666666 x³ + 0.041666666666666664 x⁴ + [-4.63936, 3.17106]

julia> xtm1_order4 = TaylorModel1( Taylor1(xN, 4), 0..0, 0..0, -0.5 .. 0.5)
  1.0 x + [0, 0]

julia> new_xtm1_order4, _ = TaylorSeries.fixorder(xtm1_order5, xtm1_order4)
ERROR: MethodError: no method matching TaylorModel1(::Taylor1{TaylorN{Float64}}, ::TaylorN{Interval{Float64}}, ::Interval{Float64}, ::Interval{Float64})
...
```

cc: @AnderGray

### Additional contract requirements

- `TaylorModels.bound_truncation(::Type{TaylorModel1}, a::Taylor1{TaylorN{T}}, aux::Interval, order::Int)` returns `zero(aux)` whenever `order` is greater than or equal to the current order of `a`.
