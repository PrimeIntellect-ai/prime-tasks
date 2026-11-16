Some change in `Rewriters.Postwalk` or `Rewriters.PassThrough` causes bug crashing Catalyst steady state solving
This is kind of weird, but something has happened. I was enabling a Catalyst test (which had been disabled due to other reasons). However, it now catches some new error which seems to originate in Symbolics.

Here is a minimal example:
```julia
using Symbolics
import Symbolics: unwrap, wrap

# Parses and expression and return a version where any exponents that are Float64 (but an int, like 2.0) are turned into Int64s.
function make_int_exps(expr)
    wrap(Rewriters.Postwalk(Rewriters.PassThrough(___make_int_exps))(unwrap(expr))).val
end
function ___make_int_exps(expr)
    !iscall(expr) && return expr
    if (operation(expr) == ^)
        if isinteger(sorted_arguments(expr)[2])
            return sorted_arguments(expr)[1]^Int64(sorted_arguments(expr)[2])
        else
            error("An non integer ($(sorted_arguments(expr)[2])) was found as a variable exponent. Non-integer exponents are not supported for homotopy continuation based steady state finding.")
        end
    end
end

@variables t X(t)
eq = 2.0*X^3.0
make_int_exps(eq) # returns `2.0(X(t)^3.0)`, should be `2.0(X(t)^3)`
```

Previously this converted the exponential to an integer (`3`), but that behaviour does not work any more. I got some help with this code from Shashi, so not really sure exactly how `Rewriters.Postwalk` and `Rewriters.PassThrough` works, so not sure what exactly is going wrong. However, on previous versions, this did use to work.
