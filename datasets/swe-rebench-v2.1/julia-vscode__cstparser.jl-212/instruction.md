Can't parse function that uses `where` in kw args
From https://github.com/domluna/JuliaFormatter.jl/issues/319, @domluna reduced this to be a CSTParser bug:

```julia
julia> a = """
       function fill_between!(x, y1, y2; where = nothing, scene = current_scene(), kw_args...)
          xv, ylow, yhigh = fill_view(x, y1, y2, where)
          band!(scene, xv, ylow, yhigh; kw_args...)
       end"""
"function fill_between!(x, y1, y2; where = nothing, scene = current_scene(), kw_args...)\n   xv, ylow, yhigh = fill_view(x, y1, y2, where)\n   band!(scene, xv, ylow, yhigh; kw_args...)\nend"

julia> CSTParser.parse(a)
  1:185 FunctionDef
  1:9    FUNCTION
 10:42   WhereOpCall
 10:34    Call
 10:22     fill_between!
 23:23     (
 24:24     x
 25:26     ,
 27:28     y1
 29:30     ,
 31:34     y2
 35:34     ErrorToken( CSTParser.UnexpectedToken)
 35:34      )
 35:40    OP: WHERE
 41:42    ErrorToken( CSTParser.UnexpectedAssignmentOp)
 41:42     OP: EQ
 43:182  Block
 43:91    BinaryOpCall
 43:57     TupleH
 43:49      nothing
 50:51      ,
 52:57      scene
 58:59     OP: EQ
 60:91     TupleH
 60:74      Call
 60:72       current_scene
 73:73       (
 74:74       )
 75:76      ,
 77:91      ErrorToken
 77:86       UnaryOpCall
 77:83        kw_args
 84:86        OP: DDDOT
 87:91       ErrorToken( CSTParser.Unknown)
 87:91        )
 92:140   BinaryOpCall
 92:107    TupleH
 92:93      xv
 94:95      ,
 96:99      ylow
100:101     ,
102:107     yhigh
108:109    OP: EQ
110:140    Call
110:118     fill_view
119:119     (
120:120     x
121:122     ,
123:124     y1
125:126     ,
127:128     y2
129:130     ,
131:135     where
136:140     )
141:182   Call
141:145    band!
146:146    (
147:151    scene
152:153    ,
154:155    xv
156:157    ,
158:161    ylow
162:163    ,
164:170    yhigh
171:180    Parameters
171:180     UnaryOpCall
171:177      kw_args
178:180      OP: DDDOT
181:182    )
183:185  END
```
