error when printing the minimum / maximum of an array of int
### Describe the bug

A Fortran runtime error occurs when printing the minimum value of an array of int
(I am not fully sure this is a bug, but certainly a strange behaviour of the print function)

### To Reproduce
Provide code to reproduce the behavior:
```python
import numpy as np


def test_print_float():
    ii = np.zeros(shape=2)
    ii[:] = 1
    print(" ii = ", ii)
    a = np.amin(ii)
    print(a)
    print(np.amin(ii))

def test_print_int():
    ii = np.empty(shape=2, dtype='int')
    ii[:] = 1
    print(" ii = ", ii)
    a = np.amin(ii)
    if a == np.amin(ii):
        print('OK')
    else:
        print('NOT OK')
    print(a)
    print(np.amin(ii))
```

### Error details
The generated fortran function is
```fortran
module debug_pyccel_module


  use, intrinsic :: ISO_C_Binding, only : f64 => C_DOUBLE , i64 => &
        C_INT64_T
  use, intrinsic :: ISO_FORTRAN_ENV, only : stdout => output_unit
  implicit none

  contains

  !........................................
  subroutine test_print_float()

    implicit none

    real(f64), allocatable :: ii(:)
    real(f64) :: a
    integer(i64) :: i

    allocate(ii(0:1_i64))
    ii = 0.0_f64
    ii(:) = 1_i64
    write(stdout, '(A A)', advance="no") ' ii = ' , ' '
    write(stdout, '(A)', advance="no") '['
    do i = 0_i64, 0_i64, 1_i64
      write(stdout, '(F0.12 A)', advance="no") ii(i) , ' '
    end do
    write(stdout, '(F0.12 A)', advance="no") ii(1_i64) , ']'
    write(stdout, '()', advance="yes")
    a = minval(ii)
    write(stdout, '(F0.12)', advance="yes") a
    write(stdout, '(F0.12)', advance="yes") minval(ii)
    if (allocated(ii)) then
      deallocate(ii)
    end if

  end subroutine test_print_float
  !........................................

  !........................................
  [HIDDEN]
  !........................................

end module debug_pyccel_module
```

The error message when running `test_print_int()` is
```sh
 ii =  [1 1]
OK
1
At line 65 of file debug_pyccel_module.f90 (unit = 6, file = 'stdout')
Fortran runtime error: Expected INTEGER for item 1 in formatted transfer, got REAL
(I0)
 ^
 ```

### Expected behavior
The print command `print(np.amin(ii))` should not give an error, but just print `1`
Note: the function `test_print_float()` yields no error.

### Language
Fortran

### Additional context
I am using pyccel 1.7.3 and python 3.11
The same error is obtained with np.min, np.amax and np.max

### Additional contract requirements

- In Fortran, printing the result of an integer-array reduction with `np.amin` or `np.min`, or with `np.amax` or `np.max`, must complete without a runtime error and print the corresponding minimum or maximum value.
