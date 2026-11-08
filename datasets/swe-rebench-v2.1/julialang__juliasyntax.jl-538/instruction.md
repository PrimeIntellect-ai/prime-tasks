ParseError when typing multi-line input with comment
Since the backport of #397 to `release-0.4` (julia nightly since https://github.com/JuliaLang/julia/pull/56110) and also on `main`, I cannot enter multi-line input which contains comments. Once I press return after the comment it directly aborts with a `ParseError` instead of letting me continue the input in the next line:
```julia
julia> function bla()
       a=1
       b=2 #a comment
ERROR: ParseError:
# Error @ REPL[2]:3:4
a=1
b=2 #a comment
#  └ ── Expected `end`
Stacktrace:
 [1] top-level scope
   @ REPL:1
```
The same happens when entering an array in multiple lines:
```julia
julia> arr = [
       1,
       2,
       3, # i like this number
ERROR: ParseError:
# Error @ REPL[3]:4:3
2,
3, # i like this number
# └ ── Expected `]` or `,`
Stacktrace:
 [1] top-level scope
   @ REPL:1
```
Note that this applies only to entering this manually line by line, pasting multi-line strings with comments works fine.

With previous julia nightly (or JuliaSyntax.jl) versions the error appears only on the second consecutive empty line:
```julia
julia> arr = [
       1,
       2,
       3, # i like this number


ERROR: ParseError:
# Error @ REPL[33]:5:2
3, # i like this number

#└ ── Expected `]`
Stacktrace:
 [1] top-level scope
   @ REPL:1
```

### Additional contract requirements

- For multiline input containing comments (for example `function f()\nbody #comment` or `a = [\n1,\n2, #comment`), including when two blank lines follow the trailing comment, `Base.incomplete_tag` on the parsed expression must not be `:none` in either `:statement` or `:all` mode, so that the REPL continues the input rather than aborting with a `ParseError`.
