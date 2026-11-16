[NEMO] Implicitly-declared subroutine arguments are lost
Chris has found that if PSyclone encounters code such as:

    module my_mod

    contains

    subroutine my_sub(iarg)
      write(*,*) iarg
    end subroutine my_sub

    end module my_mod

then PSyclone loses the `iarg` argument to the subroutine (presumably because it is never explicitly declared) and the resulting code is wrong.
