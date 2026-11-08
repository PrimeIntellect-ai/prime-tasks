Missing boolean cast in Fortran code
### Describe the bug
 Python scripts written to test the fix for the issue #1762 #1641, results in compilation error for the fortran language. Please let me know if there is any existing issue which tracks this behavior.

### To Reproduce
Provide code to reproduce the behavior:
Example 1:
```python
@template('T1', ['bool[:,:]', 'int[:,:]', 'int8[:,:]', 'int16[:,:]', 'int32[:,:]', 'int64[:,:]', 'float[:,:]', 'float32[:,:]', 'float64[:,:]', 'complex64[:,:]', 'complex128[:,:]'])
def create_bool_copy(a : 'T1'):
    c = np.array(a, dtype='bool')
    return c

if __name__ == '__main__':
    arr = np.ones((2,2), dtype='int16')
    arr[1, 1] = 256
    arr[0, 1] = -1
    arr[1, 0] = 64
    arr[0, 0] = -1
    print(arr)
    arr2 = create_bool_copy(arr)
    print(arr2)
```
Example 2:
```python
def create_float_copy(a : 'bool[:,:]'):
    c = np.array(a, dtype='float32')
    return c

if __name__ == '__main__':
    arr = np.ones((2,2), dtype='bool')
    print(arr)
    arr2 = create_float_copy(arr)
    print(arr2)
```
### Error details
Provide the generated code, or the error message:
```
ERROR at Fortran compilation stage
Traceback (most recent call last):
  File "/home/varadarajan/softwares/my-jupyter-env/bin/pyccel", line 8, in <module>
    sys.exit(pyccel())
  File "/home/varadarajan/softwares/my-jupyter-env/lib/python3.10/site-packages/pyccel/commands/console.py", line 266, in pyccel
    execute_pyccel(filename,
  File "/home/varadarajan/softwares/my-jupyter-env/lib/python3.10/site-packages/pyccel/codegen/pipeline.py", line 378, in execute_pyccel
    src_compiler.compile_module(compile_obj=mod_obj,
  File "/home/varadarajan/softwares/my-jupyter-env/lib/python3.10/site-packages/pyccel/codegen/compiling/compilers.py", line 355, in compile_module
    self.run_command(cmd, verbose)
  File "/home/varadarajan/softwares/my-jupyter-env/lib/python3.10/site-packages/pyccel/codegen/compiling/compilers.py", line 500, in run_command
    raise RuntimeError(err_msg)
RuntimeError: Failed to build module
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:162:8:

  162 |     c = a
      |        1
Warning: Extension: Conversion from INTEGER(4) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:146:8:

  146 |     c = a
      |        1
Warning: Extension: Conversion from INTEGER(1) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:114:8:

  114 |     c = a
      |        1
Warning: Extension: Conversion from INTEGER(8) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:98:8:

   98 |     c = a
      |        1
Warning: Extension: Conversion from INTEGER(2) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:82:8:

   82 |     c = a
      |        1
Error: Cannot convert REAL(4) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:66:8:

   66 |     c = a
      |        1
Error: Cannot convert COMPLEX(8) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:50:8:

   50 |     c = a
      |        1
Error: Cannot convert COMPLEX(4) to LOGICAL(1) at (1)
/home/varadarajan/softwares/Pyccel/my_progs/__pyccel__/test1_template.f90:34:8:

   34 |     c = a
      |        1
Error: Cannot convert REAL(8) to LOGICAL(1) at (1)
```

### Expected behavior
An error message why it cannot create a fortran executable.

### Language
Fortran

### Additional context
If there is an bug id which tracks this issue, I can update the Pytest fortran skip part for #1762

### Additional contract requirements

- For the Fortran target, `np.array(a, dtype=...)` conversions must compile and produce values consistent with NumPy. In particular, conversion to `dtype='bool'` must work when `a` has any of these dtypes: bool, int, int8, int16, int32, int64, float, float32, float64, complex64, or complex128. Boolean values must be false for zero values and true for nonzero values.
- Conversion from boolean arrays to float or complex arrays must also compile and produce values consistent with NumPy.
- The sentence under “Expected behavior” in the report describes the observed compilation failure, not the intended outcome; the intended behavior is successful compilation and correct conversion results.
