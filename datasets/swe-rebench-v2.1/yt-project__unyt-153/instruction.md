"mu," fonts in matplotlib, and unicode fallbacks
The "mu" unicode character seems to have some interesting things going on in matplotlib.  I'm not issuing a pull request because I have a suspicion that there are more complex things going on than I realize.

matplotlib uses the `FT_get_glyph_index` function when it's attempting to identify a symbol, and then uses the result of that to identify the appropriate replacement for fallbacks.  Using the `cm` font system, this shows up when using unicode characters.

The subtlety seems to show up when using `\u00b5` versus `\u03bc` to represent the mu character.  In `unyt/_unit_lookup_table.py`, both b5 and3bc show up in the `unit_prefixes`.  (As a sidenote, I think evidence of the problem is visible in vim if you search for u00b5 and u03bc -- searching for the former includes the latter, but not the reverse.)  Elsewhere in the code, 00b5 shows up in things like `generate_name_alternatives` etc, but u03bc does not.

[HIDDEN]  This character returns a *positive* in `FT_get_glyph_index`, so it does *not* trigger the "replace with a symbol from STIX" code path in matplotlib, and instead thinks it has correctly identified the glyph as "grave" (backtick I think).  So it proceeds using this as the symbol instead of using the backup symbol.

What I *think* is the "pragmatic" way forward would be to [HIDDEN]  Unfortunately, my reading of the codenames in Unicode (which are emphasized in `_unit_lookup_table.py` as drawn from Juan Reyero) is that the *correct* one is really u00b5, and u03bc really is what should be the more specific implementation...  So I'm not sure even what to suggest, since it kind of reads to me like we're bumping up at the ugly space between pragmatism and idealism.

Anyway here's a script that demonstrates:

```
mport matplotlib.pyplot as plt
import numpy as np
from matplotlib.style import context
style = {
    'mathtext.fontset': 'cm',
    'mathtext.fallback_to_cm': True,
}
with context(style, after_reset=False):
    labels = ['$\\rm{x\\ \\ (\\rm{' + '\u03bc' + 'm})}$', '$\\rm{y\\ \\ (\\rm{' + '\u00b5' + '})}$']
    t = np.arange(0.0, 2.0, 0.01)
    s = 1 + np.sin(2 * np.pi * t)
    fig, ax = plt.subplots()
    ax.plot(t, s)
    ax.set(xlabel=labels[0], ylabel=labels[1],
           title='About as simple as it gets, folks')
    ax.grid()
    fig.savefig("test.png")
```

### Additional contract requirements

- Unit symbols emitted for micro-prefixed units must use Greek small letter mu (U+03BC), not the micro sign (U+00B5).
