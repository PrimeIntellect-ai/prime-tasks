Chain rule not working as expected with Symbolic array elements
I'm attempting to use Symbolics to solve some perturbation problems involving using symbolic array variables to generate series. However, no matter what I try, I've been unable to get the chain rule to apply the elements of the array. I understand that array differentiation is currently supported, but here I'm only working with elements of the array so it seems different.

Below is an example of the problem I've been running into:
```
using Symbolics
@variables t T(t) y(T)[1:3]
Dt = Differential(t)
expand_derivatives(Dt(y[1]))
```
$$
\begin{equation}
\frac{\mathrm{d} y\left( T\left( t \right) \right)_{1}}{\mathrm{d}t}
\end{equation}
 $$

Instead, I would expect it to behave more like the following:
```
@variables x(T)
expand_derivatives(Dt(x))
```
$$
\begin{equation}
\frac{\mathrm{d} x\left( T\left( t \right) \right)}{T\left( t \right)} \frac{\mathrm{d} T\left( t \right)}{\mathrm{d}t}
\end{equation}
 $$

[HIDDEN]

This change results in:
```
expand_derivatives(Dt(y[1]))
```

$$
\begin{equation}
\frac{\mathrm{d} y\left( T\left( t \right) \right)_{1}}{T\left( t \right)} \frac{\mathrm{d} T\left( t \right)}{\mathrm{d}t}
\end{equation}
 $$

Original Discourse link: https://discourse.julialang.org/t/chain-rule-not-working-as-expected-with-symbolic-series/123598

### Additional contract requirements

- Expanding the derivative of an indexed element of a symbolic array must apply the chain rule through its symbolic dependency, analogously to a scalar dependent variable.
