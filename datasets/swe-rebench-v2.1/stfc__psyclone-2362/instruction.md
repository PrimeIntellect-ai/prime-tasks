PSyclone converts modules containing the `save` attribute to CodeBlock
I'm not sure exactly what this behaviour means in the context of Fortran, but I came across some code which didn't convert a module into a `Container` when using PSyclone to do some source to source translation, due to the presence of the `save` attribute.

Not sure if this is worth fixing or not - if its a small change then perhaps (but I don't know how it might affect the rest of the code, like the `save` attribute in general).

Replicator test.

```
    def test_container_creation(fortran_reader):
        code = '''module test_mod
        implicit none
        private
        public :: var1
        public :: var2, var3

        save

        integer, dimension(123) :: var2, var3

        contains

        subroutine var1()
        var2(:) = 0
        var3(:) = 0
        end subroutine var1

        end module'''

        psyir = fortran_reader.psyir_from_source(code)

        print(psyir.children[0])
       assert isinstance(psyir.children[0], Container)
```
