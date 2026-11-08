Infinite loop while reading metadata
When I try to read the metadata of [Effective Java 3rd Edition by Joshua Bloch.pdf](https://github.com/bookyue/my_books/blob/53e6378b740807dc7d18f871acbf80ee72962d31/programming_language/java/Effective%20Java%203rd%20Edition%20by%20Joshua%20Bloch.pdf) it takes extremely long. It might even be an infinite loop.

## Environment

Which environment were you using when you encountered the problem?

```bash
$ python -m platform
Linux-5.4.0-125-generic-x86_64-with-debian-bullseye-sid

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
2.10.5
```

## Code + PDF

This is a minimal, complete example that shows the issue:

```python
from PyPDF2 import PdfReader
import time

t0 = time.time()
reader = PdfReader("Effective Java 3rd Edition by Joshua Bloch.pdf")
t1 = time.time()
print(f"Creating PDF Reader: {t1-t0:.2f} seconds")

t0 = time.time()
metadata = reader.metadata
t1 = time.time()
print(f"Reading metadata: {t1-t0:.2f} seconds")
```

The PDF: [Effective Java 3rd Edition by Joshua Bloch.pdf](https://github.com/bookyue/my_books/blob/53e6378b740807dc7d18f871acbf80ee72962d31/programming_language/java/Effective%20Java%203rd%20Edition%20by%20Joshua%20Bloch.pdf)

### Additional contract requirements

- Reading `reader.metadata` for a document whose Info dictionary contains an invalid token (for example `@@@`) must finish promptly, without an extreme delay or an endless loop, and must not raise an exception when the reader is not in strict mode.
