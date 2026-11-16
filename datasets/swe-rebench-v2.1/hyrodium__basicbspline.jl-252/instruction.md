`refinement` is not type-stable
The following function `r` is not type-stable.

```julia
julia> using BasicBSpline

julia> k = KnotVector(rand(12))
KnotVector([0.024885878108435344, 0.1135410183212171, 0.17203785287918527, 0.2931216734788268, 0.46010004333534293, 0.6340248134707075, 0.6826197801697019, 0.736317312313712, 0.7375293828560209, 0.9130250689726209, 0.9602880185745573, 0.9647497776183738])

julia> P = BSplineSpace{2}(k)
BSplineSpace{2, Float64}(KnotVector([0.024885878108435344, 0.1135410183212171, 0.17203785287918527, 0.2931216734788268, 0.46010004333534293, 0.6340248134707075, 0.6826197801697019, 0.736317312313712, 0.7375293828560209, 0.9130250689726209, 0.9602880185745573, 0.9647497776183738]))

julia> a = rand(dim(P))
9-element Vector{Float64}:
 0.7352550606757859
 0.4586881993320009
 0.00534648579157071
 0.27377101932655756
 0.20868358047740354
 0.7353046147958138
 0.24689508125636628
 0.14759107033296426
 0.2632878277228856

julia> M = BSplineManifold(a,(P,))
BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}((BSplineSpace{2, Float64}(KnotVector([0.024885878108435344, 0.1135410183212171, 0.17203785287918527, 0.2931216734788268, 0.46010004333534293, 0.6340248134707075, 0.6826197801697019, 0.736317312313712, 0.7375293828560209, 0.9130250689726209, 0.9602880185745573, 0.9647497776183738])),), [0.7352550606757859, 0.4586881993320009, 0.00534648579157071, 0.27377101932655756, 0.20868358047740354, 0.7353046147958138, 0.24689508125636628, 0.14759107033296426, 0.2632878277228856])

julia> r(M::BSplineManifold{1}) = refinement(M, p₊=(1,))
r (generic function with 1 method)

julia> r(M)
BSplineManifold{1, (3,), Float64, Tuple{BSplineSpace{3, Float64}}}((BSplineSpace{3, Float64}(KnotVector([0.024885878108435344, 0.1135410183212171, 0.17203785287918527, 0.17203785287918527, 0.2931216734788268, 0.2931216734788268, 0.46010004333534293, 0.46010004333534293, 0.6340248134707075, 0.6340248134707075, 0.6826197801697019, 0.6826197801697019, 0.736317312313712, 0.736317312313712, 0.7375293828560209, 0.7375293828560209, 0.9130250689726209, 0.9130250689726209, 0.9602880185745573, 0.9647497776183738])),), [0.7052253117995405, 0.5208474042370173, 0.3951691068914191, 0.09294129786446556, 0.04917231761018773, 0.22812200663351226, 0.2568132458999762, 0.21342162000054016, 0.29207559167126984, 0.6431562812168766, 0.5760951423561846, 0.25048878666321966, 0.24666803318436095, 0.18046535923542628, 0.1779741525332959, 0.25510532412657677])

julia> @code_warntype r(M)
MethodInstance for r(::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}})
  from r(M::BSplineManifold{1}) in Main at REPL[6]:1
Arguments
  #self#::Core.Const(r)
  M::BSplineManifold{1, (2,), Float64, Tuple{BSplineSpace{2, Float64}}}
Body::BSplineManifold
1 ─ %1 = (:p₊,)::Core.Const((:p₊,))
│   %2 = Core.apply_type(Core.NamedTuple, %1)::Core.Const(NamedTuple{(:p₊,)})
│   %3 = Core.tuple(1)::Core.Const((1,))
│   %4 = Core.tuple(%3)::Core.Const(((1,),))
│   %5 = (%2)(%4)::Core.Const((p₊ = (1,),))
│   %6 = Core.kwfunc(Main.refinement)::Core.Const(BasicBSpline.var"#refinement##kw"())
│   %7 = (%6)(%5, Main.refinement, M)::BSplineManifold
└──      return %7
```

[HIDDEN]

```julia
julia> using StaticArrays

julia> A = @SMatrix rand(3,4)
3×4 SMatrix{3, 4, Float64, 12} with indices SOneTo(3)×SOneTo(4):
 0.968585  0.735832  0.0643772  0.974502
 0.392632  0.863711  0.687421   0.0488318
 0.292027  0.979669  0.404775   0.538932

julia> sum(A, dims=1)
1×4 SMatrix{1, 4, Float64, 4} with indices SOneTo(1)×SOneTo(4):
 1.65324  2.57921  1.15657  1.56227

julia> sum(A, dims=Val(1))
1×4 SMatrix{1, 4, Float64, 4} with indices SOneTo(1)×SOneTo(4):
 1.65324  2.57921  1.15657  1.56227

julia> @code_warntype sum(A, dims=1)
MethodInstance for (::Base.var"#sum##kw")(::NamedTuple{(:dims,), Tuple{Int64}}, ::typeof(sum), ::SMatrix{3, 4, Float64, 12})
  from (::Base.var"#sum##kw")(::Any, ::typeof(sum), a::StaticArray{<:Tuple, T}) where T in StaticArrays at /home/hyrodium/.julia/dev/StaticArrays/src/mapreduce.jl:250
Static Parameters
  T = Float64
Arguments
  _::Core.Const(Base.var"#sum##kw"())
  @_2::NamedTuple{(:dims,), Tuple{Int64}}
  @_3::Core.Const(sum)
  a::SMatrix{3, 4, Float64, 12}
Locals
  dims::Int64
  @_6::Int64
Body::Any
1 ─ %1  = Base.haskey(@_2, :dims)::Core.Const(true)
│         Core.typeassert(%1, Core.Bool)
│         (@_6 = Base.getindex(@_2, :dims))
└──       goto #3
2 ─       Core.Const(:(@_6 = StaticArrays.:(:)))
3 ┄ %6  = @_6::Int64
│         (dims = %6)
│   %8  = (:dims,)::Core.Const((:dims,))
│   %9  = Core.apply_type(Core.NamedTuple, %8)::Core.Const(NamedTuple{(:dims,)})
│   %10 = Base.structdiff(@_2, %9)::Core.Const(NamedTuple())
│   %11 = Base.pairs(%10)::Core.Const(Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}())
│   %12 = Base.isempty(%11)::Core.Const(true)
│         Core.typeassert(%12, Core.Bool)
└──       goto #5
4 ─       Core.Const(:(Base.kwerr(@_2, @_3, a)))
5 ┄ %16 = StaticArrays.:(var"#sum#184")(dims, @_3, a)::Any
└──       return %16


julia> @code_warntype sum(A, dims=Val(1))
MethodInstance for (::Base.var"#sum##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(sum), ::SMatrix{3, 4, Float64, 12})
  from (::Base.var"#sum##kw")(::Any, ::typeof(sum), a::StaticArray{<:Tuple, T}) where T in StaticArrays at /home/hyrodium/.julia/dev/StaticArrays/src/mapreduce.jl:250
Static Parameters
  T = Float64
Arguments
  _::Core.Const(Base.var"#sum##kw"())
  @_2::Core.Const((dims = Val{1}(),))
  @_3::Core.Const(sum)
  a::SMatrix{3, 4, Float64, 12}
Locals
  dims::Val{1}
  @_6::Val{1}
Body::SMatrix{1, 4, Float64, 4}
1 ─ %1  = Base.haskey(@_2, :dims)::Core.Const(true)
│         Core.typeassert(%1, Core.Bool)
│         (@_6 = Base.getindex(@_2, :dims))
└──       goto #3
2 ─       Core.Const(:(@_6 = StaticArrays.:(:)))
3 ┄ %6  = @_6::Core.Const(Val{1}())
│         (dims = %6)
│   %8  = (:dims,)::Core.Const((:dims,))
│   %9  = Core.apply_type(Core.NamedTuple, %8)::Core.Const(NamedTuple{(:dims,)})
│   %10 = Base.structdiff(@_2, %9)::Core.Const(NamedTuple())
│   %11 = Base.pairs(%10)::Core.Const(Base.Pairs{Symbol, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}())
│   %12 = Base.isempty(%11)::Core.Const(true)
│         Core.typeassert(%12, Core.Bool)
└──       goto #5
4 ─       Core.Const(:(Base.kwerr(@_2, @_3, a)))
5 ┄ %16 = StaticArrays.:(var"#sum#184")(dims, @_3, a)::SMatrix{1, 4, Float64, 4}
└──       return %16
```

### Additional contract requirements

- `refinement` must support degree-increasing refinement with per-dimension increments supplied as a tuple of `Val` values. For concrete inputs in this form, the result must be type-stable.
