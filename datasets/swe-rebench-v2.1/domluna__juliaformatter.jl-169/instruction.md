Strange formatting
This is the output of JuliaFormatter v0.2.2:

```julia
a = f() do _
    begin
        while true
            aaaa, bbbbbbbb =     let x = y
                    @spawn begin
                        acc = acc′′
                        for _ in _
                            a
                            b
                            ccc = dddd(ee, fff, gggggggggggg)
                        end
                        return
                    end
                end |> ffff
        end
    end
end
```

Note that there is a strangely large space before `let x = y` and the indentation of `@spawn begin ... end` is incorrect.

More strangely, this formatting disappears with some subtle changes.  For example, reducing the width of the identifier `dddd` by one yields a "correct" formatting:


```julia
a = f() do _
    begin
        while true
            aaaa, bbbbbbbb = let x = y
                @spawn begin
                    acc = acc′′
                    for _ in _
                        a
                        b
                        ccc = ddd(ee, fff, gggggggggggg)
                    end
                    return
                end
            end |> ffff
        end
    end
end
```
