Error when call of function with return of an array
### Describe the bug
Error when call of function with returned of an array because of creating an unknown variable.

### To Reproduce
Python matrix0.py code:
```
import numpy as np

def Mi(x: float, M0: 'float[:, :]') -> 'float[:, :]':
    M1 = x * M0 + 1.
    return M1

def M_GEN(x: float) -> 'float[:, :, :]':
    M = np.ones((4, 4), dtype = float)
    M2 = np.empty((3, 4, 4), dtype = float)
    for i in range(3):
        M2[i] = Mi(x * i, M)
    return M2
```

pyccel matrix0.py --language=fortran

### Error details
It generates error:

```
ERROR at compilation stage
Traceback (most recent call last):
  File "/home/vadter/Programs/conda3/bin/pyccel", line 8, in <module>
    sys.exit(pyccel())
             ^^^^^^^^
  File "/home/vadter/Programs/conda3/lib/python3.12/site-packages/pyccel/commands/console.py", line 266, in pyccel
    execute_pyccel(filename,
  File "/home/vadter/Programs/conda3/lib/python3.12/site-packages/pyccel/codegen/pipeline.py", line 378, in execute_pyccel
    src_compiler.compile_module(compile_obj=mod_obj,
  File "/home/vadter/Programs/conda3/lib/python3.12/site-packages/pyccel/codegen/compiling/compilers.py", line 355, in compile_module
    self.run_command(cmd, verbose)
  File "/home/vadter/Programs/conda3/lib/python3.12/site-packages/pyccel/codegen/compiling/compilers.py", line 500, in run_command
    raise RuntimeError(err_msg)
RuntimeError: Failed to build module
/home/vadter/Documents/!Docs/mathprog/Python/PYCCEL/8_matrix/__pyccel__/matrix0.f90:41:29:

   41 |       call Mi(x * i, M, M1 = M2(:, :, i))
      |                             1
Error: Actual argument for ‘m1’ must be ALLOCATABLE at (1)
```


Fortran matrix0.f90 code:
```
module matrix0


  use, intrinsic :: ISO_C_Binding, only : f64 => C_DOUBLE , i64 => &
        C_INT64_T
  implicit none

  contains

  !........................................
  subroutine Mi(x, M0, M1)

    implicit none

    real(f64), allocatable, intent(out) :: M1(:,:)
    real(f64), value :: x
    real(f64), intent(in) :: M0(0:,0:)

    allocate(M1(0:size(M0, 1_i64, i64) - 1_i64, 0:size(M0, 2_i64, i64) - &
          1_i64))
    M1 = x * M0 + 1.0_f64
    return

  end subroutine Mi
  !........................................

  !........................................
  subroutine M_GEN(x, M2)

    implicit none

    real(f64), allocatable, intent(out) :: M2(:,:,:)
    real(f64), value :: x
    real(f64), allocatable :: M(:,:)
    integer(i64) :: i

    allocate(M(0:3_i64, 0:3_i64))
    M = 1.0_f64
    allocate(M2(0:3_i64, 0:3_i64, 0:2_i64))
    do i = 0_i64, 2_i64
      call Mi(x * i, M, M1 = M2(:, :, i)) ! <------- Unknown M1
    end do
    if (allocated(M)) then
      deallocate(M)
    end if
    return

  end subroutine M_GEN
  !........................................

end module matrix0
```

### Expected behavior
Correct substitution of a variable in a subroutine: [HIDDEN].

### Language
Fortran

### Additional context

### Additional contract requirements

When the reproduced example is translated to Fortran, it must compile successfully. The two-dimensional array returned by each call to `Mi` must populate the corresponding two-dimensional slice of `M2`, so that `M_GEN` returns the same tensor values as the Python example.
