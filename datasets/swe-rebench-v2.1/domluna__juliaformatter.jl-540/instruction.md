Cannot set trailing_comma=nothing in .JuliaFormatter.toml
As far as I know, TOML does not have a `nothing` value, so there is no way to set `trailing_comma = nothing` in `.JuliaFormatter.toml`.

The easiest solution would probably be to [HIDDEN].

### Additional contract requirements

- When `.JuliaFormatter.toml` sets `trailing_comma = "nothing"`, treat it as the `nothing` setting for `trailing_comma`.
