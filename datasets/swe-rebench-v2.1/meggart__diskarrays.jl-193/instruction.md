`zip` triggers lots of invalidations
We have a workload over at [ClimaAtmos.jl](https://github.com/CliMA/ClimaAtmos.jl), where we use SnoopCompile's [invalidations script](https://timholy.github.io/SnoopCompile.jl/dev/tutorial/#Cut-to-the-Chase:-A-copy-paste-analysis-of-invalidations), and the result is:

```
[ Info: 4296 methods invalidated for 178 functions (showing 10 functions)
┌─────────────────────────────────────────────────────────┬───────────────┬───────────────┬─────────────────┐
│ <file name>:<line number>                               │ Function Name │ Invalidations │ Invalidations % │
│                                                         │               │               │     (xᵢ/∑x)     │
├─────────────────────────────────────────────────────────┼───────────────┼───────────────┼─────────────────┤
│ DiskArrays/bZBJE/src/zip.jl:83                          │      zip      │     3247      │       14        │
│ DiskArrays/bZBJE/src/zip.jl:70                          │      zip      │     3247      │       14        │
│ DiskArrays/bZBJE/src/zip.jl:83                          │      zip      │     3247      │       14        │
│ FillArrays/eOEVm/src/fillbroadcast.jl:78                │  broadcasted  │     1220      │        5        │
│ CommonDataModel/G3moc/src/groupby.jl:267                │  broadcasted  │     1220      │        5        │
│ ClimaCore/ANgUC/src/MatrixFields/field_name_dict.jl:331 │  broadcasted  │     1220      │        5        │
│ ClimaCore/ANgUC/src/MatrixFields/field_name_dict.jl:475 │  broadcasted  │     1220      │        5        │
│ ClimaCore/ANgUC/src/MatrixFields/lazy_operators.jl:44   │  broadcasted  │     1220      │        5        │
│ GeometryBasics/ebXl0/src/offsetintegers.jl:40           │    convert    │      834      │        4        │
│ DiskArrays/bZBJE/src/generator.jl:53                    │   Generator   │      439      │        2        │
└─────────────────────────────────────────────────────────┴───────────────┴───────────────┴─────────────────┘
```
So, DiskArrays' [`zip`](https://github.com/meggart/DiskArrays.jl/blob/64f4de86ec3ab921759d7372c19766a463c58e61/src/zip.jl#L81-L83) seems to invalidate 9741 methods.

### Additional contract requirements

- Loading DiskArrays should avoid the excessive method-invalidation cascade caused by its zip integration while retaining elementwise pairing of corresponding values from each input.
