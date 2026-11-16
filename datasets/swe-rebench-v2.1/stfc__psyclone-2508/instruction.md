InlineTrans should ignore formal arguments when checking for symbol clashes
 As reported by Hugo, the following code:

    def test_apply_argument_clash(fortran_reader, fortran_writer):
        '''
        Check that the dummy arguments to the inlined routine are not included
        when checking for clashes (since they will be replaced by the formal
        arguments to the call).
        '''

        code_clash = """
      subroutine run_it()
        integer :: i
        integer :: Istr
        real :: a(10)

        do i=Istr,10
          a(i) = 1.0
        end do

        call sub(Istr)
      end subroutine run_it

      subroutine sub(Istr)
        integer :: Istr
        real :: x
        x = 2.0*x
        call sub_sub(Istr)
      end subroutine sub

      subroutine sub_sub(Istr)
        integer :: i
        integer :: Istr
        real :: b(10)

        do i=Istr,10
          b(i) = 1.0
        end do
      end subroutine sub_sub"""

        psyir = fortran_reader.psyir_from_source(code_clash)
        call = psyir.walk(Call)[1]
        inline_trans = InlineTrans()
        inline_trans.apply(call)

[HIDDEN] Hugo has kindly provided a patch for this which I'll use.

### Additional contract requirements

- A name clash involving a formal argument of the routine being inlined must not, by itself, prevent `InlineTrans` from inlining the call.
- References to an inlined routine’s formal argument must resolve to the corresponding actual argument supplied at the call site.
