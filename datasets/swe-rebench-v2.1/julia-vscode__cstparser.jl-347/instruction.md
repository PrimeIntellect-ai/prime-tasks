CSTParser cannot parse for loops in a quoted macro
```julia
julia> using CSTParser

julia> CSTParser.parse(":(@simd ivdep for i_1 in axes(dst, 1) end)")
  1:42  quote
  1:41   brackets
  1:39    errortoken
  1:36     generator
  1:12      macrocall
  1:6        @simd
  7:6        NOTHING: nothing
  7:12       ivdep
 13:32        1:0   OP: =
 13:16       i_1
 17:29       call
 17:20        axes
 21:23        dst
 24:24        INTEGER: 1
 37:39     errortoken( CSTParser.UnexpectedToken)
 37:39      END
```
