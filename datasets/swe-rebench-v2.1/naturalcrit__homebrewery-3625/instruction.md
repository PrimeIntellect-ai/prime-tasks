Math functions with multiple parameters cannot take variable names
### Renderer

v3

### Browser

Chrome

### Operating System

Windows

### What happened?

The expectation is the reproduction code will return `2`; instead it returns `$[min(2,DexMod)]`

See reproduction brew here - https://homebrewery.naturalcrit.com/share/VE5qZsAsuAfk

### Code

```gfm
[DexMod]: 4

$[min(2,DexMod)]
```
