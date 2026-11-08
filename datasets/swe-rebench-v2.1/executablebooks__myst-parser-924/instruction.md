For v3.0.1: If the last directive option has an empty value then it is omitted
### What version of `myst-parser` are you using?

3.0.0

### What version dependencies are you using?

sphinx=7.3.7
docutils=0.20.1


### What operating system are you using?

Linux

### Describe the Bug

The glob patterns defined in a toctree directive do not work with `3.0.0` anymore.

### Expected Behavior

_No response_

### To Reproduce

````markdown
```{toctree}
---
maxdepth: 2
caption: Contents
glob:
---
path*/index
pages/**
*/index
```
````

### Additional contract requirements

- A final directive option with no explicit value must be retained rather than omitted. In particular, the reproduced toctree must recognize `glob:` so its glob patterns continue to work.
