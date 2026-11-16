Allocate with mold= parameter
This is valid Fortran, but not accepted by fparser:
```
subroutine a(b1)
   integer, dimension(:,:), allocatable :: b1
   integer, dimension(:,:), allocatable :: a1
   allocate(a1, mold=b1)
end subroutine a
```
Supporting the `mold` argument makes it easier to create the kernel-extraction driver (since we can then allocate variables without having to analyse the number of dimensions). It's not urgent, since I have a work around.

### Additional contract requirements

- Add a public class `Alloc_Opt` in module `fparser.two.Fortran2003` that parses a single allocation-option clause. It accepts `STAT = <stat-variable>`, `ERRMSG = <errmsg-variable>` and `SOURCE = <source-expr>`. The keyword is case-insensitive and is upper-cased in the parsed result. For `STAT = a`, `str(obj)` yields `"STAT = a"` and `repr(obj)` yields `"Alloc_Opt('STAT', Name('a'))"`. It raises `NoMatchError` (from `fparser.two.utils`) when the string does not match any allowed keyword.
- Add a public class `Alloc_Opt` in module `fparser.two.Fortran2008` that accepts `STAT = <stat-variable>`, `ERRMSG = <errmsg-variable>`, `SOURCE = <source-expr>` and `MOLD = <source-expr>`.
- Add a public class `Allocate_Stmt` in module `fparser.two.Fortran2003` that parses a full ALLOCATE statement, with an optional type-spec, a comma-separated list of allocate-objects and an optional list of alloc-opt clauses. `str(obj)` returns the canonical upper-case form with spaces around commas and `=`: `allocate(a,b)` yields `"ALLOCATE(a, b)"`, `allocate(real::a)` yields `"ALLOCATE(REAL::a)"`, and `allocate(real(kind=8)::a, stat=b, source=c//d)` yields `"ALLOCATE(REAL(KIND = 8)::a, STAT = b, SOURCE = c // d)"`.
- Add a public class `Allocate_Stmt` in module `fparser.two.Fortran2008` that parses a full ALLOCATE statement including an optional `MOLD = <source-expr>` allocation option.
- The Fortran2008 parser (`fparser.two.parser.ParserFactory().create(std="f2008")`) accepts an ALLOCATE statement containing `MOLD = <source-expr>`.
