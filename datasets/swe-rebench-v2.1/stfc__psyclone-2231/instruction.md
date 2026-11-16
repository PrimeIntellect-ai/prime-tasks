LFRic alg layer error when using PSyIR: visibility symbol
`lfric_xios_tie_axis_mod.x90` causes PSyclone to fail when using the new PSyIR algorithm parsing approach. A cut down version of the problem is below. The problem appears to be with the use of `public :: update_interface` with the backend saying that it is not declared anywhere.

```
module test
  abstract interface
     subroutine update_interface()
     end subroutine update_interface
  end interface
  public :: update_interface
contains
  subroutine alg()
    use constants_mod,     only: r_def
    use field_mod,         only: field_type
    type(field_type)       :: a
    real(r_def)            :: x
    call invoke(inc_a_times_x(x,a))
  end subroutine alg
end module test
```

### Additional contract requirements

- Add a public function `_find_or_create_unresolved_symbol(location, name, scope_limit=None, **kargs)` in module `psyclone.psyir.frontend.fparser2`. It searches the scope hierarchy starting from the PSyIR node `location` for a symbol named `name`, stopping at `scope_limit` when that is supplied. If no matching symbol is found but the name can be introduced by a wildcard import or by an interface whose declaration is hidden, it creates and returns a new symbol with an `UnresolvedInterface`; otherwise it raises `SymbolError`.
- If `location` is not a PSyIR `Node`, raise `TypeError` whose message contains: `The location argument 'hello' provided to _find_or_create_unresolved_symbol() is not of type `Node`.`
- If `scope_limit` is not a PSyIR `Node`, raise `TypeError` whose message contains: `The scope_limit argument 'hello' provided to _find_or_create_unresolved_symbol() is not of type `Node`.`
- If `scope_limit` is not an ancestor of `location`, raise `ValueError` whose message contains: `The scope_limit node 'Reference[name:'alpha']' provided to _find_or_create_unresolved_symbol() is not an ancestor of this node 'Reference[name:'alpha']'.`
- When a module declares `public :: update_interface` and `update_interface` is declared inside an `abstract interface`, the generated Fortran must contain `public\n` and must not contain `public :: update_interface`.
- When a module declares `private :: update_interface` and `update_interface` is declared inside an `abstract interface`, the generated Fortran must contain `private :: update_interface`.
