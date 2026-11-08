`let x = 1 #` ParseError
```julia
julia> let x = 1
       x
       end
1

julia> let x = 1 #
ERROR: ParseError:
# Error @ REPL[2]:1:10
let x = 1 #
#        └ ── premature end of input
Stacktrace:
 [1] top-level scope
   @ none:1
```
from https://discourse.julialang.org/t/let-x-1-parseerror/130050?u=waltermadelim

### Additional contract requirements

When parsing `let x = 1 #` at end of input (including with comment text after `#`), treat the input as incomplete rather than as a completed expression or a parse error. The specific incomplete category is not prescribed.
