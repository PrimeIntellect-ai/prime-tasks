[PARSE BUG]: static inline function
### Problem description

Parsing mkl header file,

```python
filename = /path/to/mkl_direct_call.h
pp = make_gcc_preprocessor(
    defines=["MKL_DIRECT_CALL 1"],
)
options = ParserOptions(verbose=False, preprocessor=pp)
data = parse_file(filename, options=options)
```

```bash
mkl_direct_call.h:851: parse error evaluating 'double': unexpected 'double'
```

### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
/* {S,D}DOT_DIRECT */
static __inline double mkl_dc_ddot_convert(const MKL_INT *n, const double* x, const MKL_INT *incx, const double *y, const MKL_INT *incy) {
    double ret = 0.0;
    if (MKL_DC_DDOT_CHECKSIZE(n)) {
        ret = mkl_dc_ddot((n), (x), (incx), (y), (incy));
    } else {
        ret = ddot_direct((n), (x), (incx), (y), (incy));
    }
    return ret;
}
```
