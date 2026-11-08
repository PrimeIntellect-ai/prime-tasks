`@variable` declarations returning empty container should have `VariableRef` element type
**Is your feature request related to a problem? Please describe.**
On latest tagged, `@variable(m, x[1:0])` returns a `Vector{Any}`.  Because of this, code which uses `x` as an input cannot infer the containers element type.  An example of how this can go wrong is if one calls `sum(x)` it will throw an error because there is no `zero(Any)`, where as `zero(VariableRef)` gives a zero `AffExpr`.

**Describe the solution you'd like**
[HIDDEN]  However, I realize that this ignores the possibility of other variable types, so, alternatively, it might be nice to add a keyword argument.  Preferably, this would still default to something other than `Any`.

**Describe alternatives you've considered**
You can `convert` the result, but it seems undesirable to have to do the check.

**Additional context**
I think previous versions of JuMP returned a `VariableRef` container, but I haven't verified this.

### Additional contract requirements

- For an empty indexed `@variable` declaration of ordinary variables, the returned container must have `VariableRef` as its element type when that type can be determined.
