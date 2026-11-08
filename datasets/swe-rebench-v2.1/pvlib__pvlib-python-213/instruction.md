Bug in dirint: pressure is not [HIDDEN]
The dirint function fails to [HIDDEN]. This effects disc's airmass calculation, which effects the disc dni calculation, which effects the dirint dni. I'll fix this soon.

### Additional contract requirements

- When a caller supplies pressure to `dirint`, that pressure must be reflected in the resulting DNI.
