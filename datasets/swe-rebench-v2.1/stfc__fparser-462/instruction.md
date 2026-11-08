Error on concatenation of two strings with a backslash
The following minimal program results in a `NoMatchError` for line 2:

```fortran
program simple
    character(len=10) :: foo = '\' // 'b'
end program simple
```

I believe this is correct Fortran--at least it compiles fine on Intel.

I'm still investigating myself. It's doesn't seem to be a problem with the regex pattern for the `concat-op`. I think it has something to do with the fact that backslashes in strings get automatically escaped to `\\` in Python.

Interestingly, if I take out the line from the program block, i.e. just:
```fortran
character(len=10) :: foo = '\' // 'b'
```
it works fine.
