Uncaught exceptions on generic file containing 'startxref' string
**Bug report**
Several issues were spotted in the PdfFileReader class.

The following code was used during tests:
```python
import sys
from PyPDF2 import PdfFileReader
from PyPDF2.utils import PyPdfError

if __name__ == "__main__":
    with open(sys.argv[1], "rb") as f:
        try:
            r = PdfFileReader(f)
        except PyPdfError:
            pass
```


output - [bug1.pdf](https://github.com/mstamy2/PyPDF2/files/6689130/bug1.pdf) :
```
Traceback (most recent call last):
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/pdf.py", line 1768, in read
    startxref = int(line)
ValueError: invalid literal for int() with base 10: b'startxref'

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "main.py", line 13, in <module>
    r = PdfFileReader(f)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/pdf.py", line 1148, in __init__
    self.read(stream)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/pdf.py", line 1773, in read
    startxref = int(line[9:].strip())
ValueError: invalid literal for int() with base 10: b''
```


output - [bug2.pdf](https://github.com/mstamy2/PyPDF2/files/6689134/bug2.pdf) :
```
Traceback (most recent call last):
  File "main.py", line 13, in <module>
    r = PdfFileReader(f)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/pdf.py", line 1148, in __init__
    self.read(stream)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/pdf.py", line 1948, in read
    stream.seek(-11, 1)
OSError: [Errno 22] Invalid argument
```


**Solution**
[HIDDEN]

### Additional contract requirements

- When `PdfFileReader` is given input beginning with `foo`, it must raise `PdfReadError` with the exact message `PDF starts with 'foo', but '%PDF-' expected`.
- For non-empty input whose header does not begin with `%PDF-`, `PdfFileReader` must reject the input with `PdfReadError`; malformed non-PDF input must not escape as an unrelated low-level exception.
