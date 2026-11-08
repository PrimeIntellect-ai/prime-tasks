Options passed PenParameter are not applied
### Short description
`pTypes.PenParameter(name="Line Style", width=5)` should initialize the wrapped pen with `width` of 5, but it remains at 1. Same applies for other style options.

### Tested environment(s)

 * PyQtGraph version: 0.12.4
 * Qt Python binding: PyQt6
 * Python version: 3.10
 * Installation method: venv / pip
