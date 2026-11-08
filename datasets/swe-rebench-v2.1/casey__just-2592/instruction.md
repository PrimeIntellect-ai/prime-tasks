Formatter strips `[private]` attribute from variables
Given a `justfile` like:

```just
[private]
foo := 'one'
bar := 'two'
_baz := 'three'

@test:
    echo {{ foo }}
    echo {{ bar }}
    echo {{ _baz }}
```
Running the formatter results in the `[private]` attribute being removed.
```sh
$ just --unstable --fmt --check
-[private]
 foo := 'one'
 bar := 'two'
 _baz := 'three'

 @test:
     echo {{ foo }}
     echo {{ bar }}
     echo {{ _baz }}
error: Formatted justfile differs from original.
```
