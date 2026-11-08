Modifications to a list via an assigned variable do not reflect in the original list
### Describe the bug
When assigning a list to another variable and then modifying the new variable, the changes are not reflected in the original list as they should be in Python.

### To Reproduce
```python
a = [1, 2, 3]
b = a
b.append(5)
print(a)
```

### Error details
Both `Fortran` and `C` interpret the assignment as a copy. Additionally, the `C` code introduces a bug as it loops over the size of `b` instead of looping over the size of `a`.
```C

int main()
{
    vec_int64_t a;
    vec_int64_t b;
    int64_t i;
    a = c_init(vec_int64_t, {INT64_C(1), INT64_C(2), INT64_C(3), INT64_C(4)});
    for (i = INT64_C(0); i < vec_int64_t_size(&b); i += INT64_C(1))
    {
        (*vec_int64_t_at_mut(&b,i)) = (*vec_int64_t_at(&a,i));
    }
    vec_int64_t_drop(&b);
    vec_int64_t_drop(&a);
    return 0;
}
```

```Fortran
  use boo
  use Vector_integer8_mod

  use, intrinsic :: ISO_C_Binding, only : i64 => C_INT64_T
  use, intrinsic :: ISO_FORTRAN_ENV, only : stdout => output_unit

  implicit none

  type(Vector_integer8) :: a
  type(Vector_integer8) :: b
  integer(i64) :: i

  a = Vector_integer8([1_i64, 2_i64, 3_i64, 4_i64])
  b = a
  call b % push_back(5_i64)
  write(stdout, '(A)', advance="no") '['
  do i = 0_i64, a % size() - 1_i64 - 1_i64
    write(stdout, '(I0, A)', advance="no") a%of(i + 1_i64) , ' '
  end do
  write(stdout, '(I0, A)', advance="no") a%of(a % size() - 1_i64 + 1_i64 &
        ) , ']'
  write(stdout, '()', advance="yes")
```

### Expected behavior
The output should be:

```bash
[1, 2, 3, 5]
```
Because in Python, lists are mutable objects, and assigning one list to another variable should create a reference to the same object. Modifying b should also modify a.

### Language
Fortran, C

### Additional context
This is issue is likely to arise with sets and dictionaries as well once their indexing is implemented.
