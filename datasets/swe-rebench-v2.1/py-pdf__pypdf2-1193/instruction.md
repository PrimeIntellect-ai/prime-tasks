Add `with ... as ...` Usage to `PdfMerger()`
## Explanation

As I need to call `write()` and `close()` in `PdfMerger()`, why not add  `__enter__` and `__exit__` method to it so I can use it more elegantly.

## Code Example

```python3
from PyPDF2 import PdfMerger

with PdfMerger(strict=False) as merger:
    for name in ["01.pdf", "02.pdf", "03.pdf", ...]:
        merger.append(name)
    merger.write("./output.pdf")
```
