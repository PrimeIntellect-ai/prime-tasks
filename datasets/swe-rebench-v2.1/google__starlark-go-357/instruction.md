a math library
Starlark seem mighty terrific. I just have a minor query about doing some math.

In starlark-go, how would one raise n to the m-th power?

In Go, I would call math.Pow(n, m). In Python, math.pow(n, m).

Another way of asking: is there a way to get at the math library from Go perhaps?

### Additional contract requirements

Go code can access the math-library facility by importing `go.starlark.net/lib/math` and using its exported `Module` to call the Starlark math functions.
