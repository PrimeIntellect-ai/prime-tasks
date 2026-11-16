Latexify of irrational numbers produces weird identity transformation
```julia
using Symbolics, Latexify
latexify(π) # produces nice L"$π$"
latexify(π ~ 0) # produces ugly L"\begin{equation} \mathrm{identity}\left( \pi \right) = 0 \end{equation}"
```
