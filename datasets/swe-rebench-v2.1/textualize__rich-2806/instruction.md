duplicated plots in jupyter
How can we avoid having duplicated plots on jupyter?

When I run

```
import gdsfactory as gf
gf.components.bend_circular()
```

I get one plot in jupyter, thanks to  defining `def _repr_html_(self)`

However when I run
```
from rich import pretty

pretty.install()
gf.components.bend_circular()
```

I get two plots of the same component.
