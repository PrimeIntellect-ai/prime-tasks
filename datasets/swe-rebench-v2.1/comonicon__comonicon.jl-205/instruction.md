[Feature Request] add dependency specification
If I want to write a script with both GPU and CPU code, then I can avoid using CUDA by using the following grammar.

```julia
@cast :(using CUDA) function f(x)
      # some GPU computation
end

@cast function g(x)
      # some CPU computation
end

@main
```

The `@main` macro calls the required using statement by inspecting `ARG[1]`.

### Additional contract requirements

The dependency-specification feature is exposed through the exported macro

```julia
@lazyload <load_expr> @cast <castable expr>
```

`@lazyload` is exported from `Comonicon`. When a script that uses `@lazyload` is
executed, `load_expr` is evaluated before the wrapped command runs if and only if
the first command-line argument (`ARGS[1]`) equals the command name derived from
the `@cast` expression. The wrapped `@cast` expression is always evaluated, and
any documentation attached to the `@lazyload` expression is preserved on the
resulting command.

The helper `Comonicon.lazyload_m(m::Module, line, load_expr, casted_expr::Expr)`
implements this behaviour and is called directly by the test suite. It throws
`ArgumentError` when `m` is not `Main`, or when `casted_expr` is not a `@cast`
macrocall.
