Assigning an array to a slice does't work in Fortran
**Describe the bug**
A wrong Fortran code is generated when trying to assign an array to a slice


**To Reproduce**
For example this python code:
```python
import numpy as np

def func(n:int):
    x = 1
    arr = np.zeros((2, n))
    arr[0:x,0:6:2] = np.array([2,5,6])
    return arr
```

Generate this Fortran code:
```bash/fortran/c
module error_0001


  use, intrinsic :: ISO_C_Binding, only : f64 => C_DOUBLE , i64 => &
        C_INT64_T
  implicit none

  contains

  !........................................
  subroutine func(n, arr)

    implicit none

    real(f64), allocatable, intent(out) :: arr(:,:)
    integer(i64), value :: n
    integer(i64) :: x

    x = 1_i64
    allocate(arr(0:n - 1_i64, 0:1_i64))
    arr = 0.0_f64
    arr(0_i64:5_i64:2_i64, 0_i64:x - 1_i64) = [2_i64, 5_i64, 6_i64]
    return

  end subroutine func
  !........................................

end module error_0001
```

Which fail in the compilation stage with this error message:
```
22 |     arr(0_i64:5_i64:2_i64, 0_i64:x - 1_i64) = [2_i64, 5_i64, 6_i64]
      |    1
Error: Incompatible ranks 2 and 1 in assignment at (1)
```

**Language**
Fortran
