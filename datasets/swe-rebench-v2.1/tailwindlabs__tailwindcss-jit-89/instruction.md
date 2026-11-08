Outline utility no longer aligned with docs
Thanks for the great improvements, this is really making fun!

While testing with an existing project I discovered that the outline utility right now differs from the `tailwindcss`' version (and the documentation as well) for it's `outline-offset`. `@tailwindcss/jit` generates f.e. `.outline-white: {outline: 2px dotted white; outline-offset: 0;}`, while the original version compiles to `.outline-white: {outline: 2px dotted white; outline-offset: 2px;}`.
