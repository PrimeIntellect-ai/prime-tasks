ValueError: invalid literal for int() with base 10: b\'0001.24.30\' in _read_standard_xref_table
See https://github.com/py-pdf/PyPDF2/issues/1269 for further details, this reports another issue I've come accross.

## Environment

Which environment were you using when you encountered the problem?

```bash
$ python -m platform
Linux-5.4.0-122-generic-x86_64-with-glibc2.29

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
2.10.3
```
## Code + PDF

This is a minimal, complete example that shows the issue:

```python
import PyPDF2
with open("BreezeManual.pdf", "rb") as f:
  pdfreader = PyPDF2.PdfFileReader(f, strict=False)
  full_content = " ".join([page.extractText() for page in pdfreader.pages])
```

PDF used above: [BreezeManual.pdf](https://github.com/wise2c-devops/breeze/blob/83d7604462d4ebdee0a9ed5fcc957e6780591993/manual/BreezeManual.pdf)

## Traceback

This is the complete Traceback I see:

``` plain
Traceback (most recent call last):
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 1775, in __init__
    super().__init__(*args, **kwargs)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 275, in __init__
    self.read(stream)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 1279, in read
    self._read_xref_tables_and_trailers(stream, startxref, xref_issue_nr)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 1427, in _read_xref_tables_and_trailers
    startxref = self._read_xref(stream)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 1449, in _read_xref
    self._read_standard_xref_table(stream)
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 1391, in _read_standard_xref_table
    offset, generation = int(offset_b), int(generation_b)
ValueError: invalid literal for int() with base 10: b'0001.24.30'
```

**The PDF can be read using a normal PDF viewer.**
