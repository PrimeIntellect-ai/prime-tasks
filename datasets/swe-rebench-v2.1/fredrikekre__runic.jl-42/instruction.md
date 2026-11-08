After linebreaks following `=`, indentation is off
For example, Runic reformats
```julia
y =
    if x
      1
    else
      2
    end
```
to
```julia
y =
    if x
    1
else
    2
end
```
which is likely not intended.

(This also applies to short-form function definitions with linebreaks after the `=`.)
