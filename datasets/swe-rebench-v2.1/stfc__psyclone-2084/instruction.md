psyir support for arrays declared with indexed bounds
We need to add support for arrays declared like a(0:n-1). At the moment they are stored as unknown fortran type, however this caused psyad to fail in poly2d_w3_reconstruction_kernel_mod.F90

### Additional contract requirements

- `psyclone.psyir.backend.fortran.FortranWriter.gen_vardecl(symbol)` returns the Fortran declaration for `symbol` as a string. When an array dimension has a specified lower bound and an unspecified (assumed) upper extent, the emitted dimension is `<lower>:` (for example, `integer, dimension(2,2,-1:) :: dummy3`).
- `psyclone.psyir.frontend.fparser2.Fparser2Reader.process_declarations(parent, spec_list, extra)` produces array datatypes for declarations with an explicit lower bound, including an assumed upper extent such as `a(4:)`, whose lower bound is the specified value and whose upper bound is `ArrayType.Extent.ATTRIBUTE`. A declaration that gives only an upper bound for an assumed-shape array, such as `a(:4)`, is invalid Fortran and raises `psyclone.errors.GenerationError`.
- `psyclone.psyir.symbols.ArrayType(datatype, shape)` accepts an unknown element type and accepts a dimension given as a 2-tuple whose upper bound is `ArrayType.Extent.ATTRIBUTE`. It rejects a lower bound of `ArrayType.Extent` with `TypeError`.
