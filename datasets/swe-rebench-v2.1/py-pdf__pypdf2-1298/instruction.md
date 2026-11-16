TypeError: 'NoneType' object is not iterable
See https://github.com/py-pdf/PyPDF2/issues/1269 for further details.

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
with open("pca_var.pdf", "rb") as f:
  pdfreader = PyPDF2.PdfFileReader(f, strict=False)
  metadata = pdfreader.metadata.copy() if pdfreader.metadata is not None else {}
```

PDF used above: [pca_var.pdf](https://github.com/tnd79bk/EbookMLCB/blob/2441571df00c59c57b431c74ef4000faaa795a52/Chapters/figs/07_DimemsionalityReduction/27_pca/latex/pca_var.pdf)

## Traceback

This is the complete Traceback I see:

```
Object 26 0 not defined.

Traceback (most recent call last):
  File "test.py", line 4, in <module>
    metadata = pdfreader.metadata.copy() if pdfreader.metadata is not None else {}
  File "/usr/local/lib/python3.8/dist-packages/PyPDF2/_reader.py", line 329, in metadata
    retval.update(obj)  # type: ignore
TypeError: 'NoneType' object is not iterable
```
