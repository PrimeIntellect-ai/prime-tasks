For Loop for loop descending order are not working in C  and Fortran
**Describe the bug**
For Loop for loop descending order are not working in C and have some bugs in Fortran

**To Reproduce**
```python
for i in range(10, 1, -1):
    print(i)
```
```Python
>> 10 9 8 7 6 5 4 3 2
```

```C
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
int main()
{
    int64_t i;

    for (i = 10; i < 1; i += -1)
    {
        printf("%ld\n", i);
    }
    return 0;
}
```
here the for loop condition should be changed.
```Fortran
program prog_test

use, intrinsic :: ISO_C_BINDING

implicit none

integer(C_INT64_T) :: i

do i = 10_C_INT64_T, 1_C_INT64_T-1_C_INT64_T, -1_C_INT64_T
  print *, i
end do

end program prog_test
```
```python
>> 10 9 8 7 6 5 4 3 2 1 0
```
here the end of the for loop is wrong
