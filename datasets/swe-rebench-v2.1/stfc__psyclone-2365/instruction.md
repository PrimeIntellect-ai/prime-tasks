`Reference2ArrayRangeTrans` introduces erroneous colon notation in `ALLOCATED` intrinsic
Consider the following example.

```fortran
module my_module
  implicit none
  public

  contains
  subroutine my_subroutine()
    integer :: my_dim
    integer, allocatable, dimension(:,:) :: my_array

    my_dim = 10

    if (.NOT.ALLOCATED(my_array)) then
      ALLOCATE(my_array(1:my_dim,1:my_dim))
    end if

  end subroutine my_subroutine

end module my_module
```

If I apply the transformation script

```python
from psyclone.psyir import nodes
from psyclone.psyir.transformations import Reference2ArrayRangeTrans
from psyclone.psyir import symbols
from psyclone.transformations import TransformationError


def trans(psy):
    for invoke in psy.invokes.invoke_list:
        for reference in invoke.schedule.walk(nodes.Reference, stop_type=nodes.Reference):
            if isinstance(reference.symbol, symbols.DataSymbol):
                try:
                    Reference2ArrayRangeTrans().apply(reference)
                except TransformationError:
                    pass
    return psy
```

then I get the output

```fortran
module my_module
  implicit none
  public

  contains
  subroutine my_subroutine()
    integer :: my_dim
    integer, allocatable, dimension(:,:) :: my_array

    my_dim = 10
    if (.NOT.ALLOCATED(my_array(:,:))) then
      ALLOCATE(my_array(1:my_dim,1:my_dim))
    end if

  end subroutine my_subroutine

end module my_module
```

The compiler I'm using (NVHPC) doesn't like the colon notation being used inside the `ALLOCATED` intrinsic call.
