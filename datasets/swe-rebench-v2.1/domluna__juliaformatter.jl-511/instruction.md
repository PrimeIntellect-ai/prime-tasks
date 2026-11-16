leading zeros for negativ float literals without space
Thanks for the great package! While using I found a small bug i wanted to report:

```julia
a = -.2
b = - .2
```
becomes
```julia
a = -.2
b = -0.2
```
which is inconsistent.

Well personally I'd rather prefer to allow the concise `.2` and `1.` syntax in general but adding another option for that might be to much to ask for 😬
