A certain PDF File triggers OSError: [Errno 22] Invalid argument
Hello,

This [file](https://drive.google.com/open?id=1JduH56YX7nxFiRF25V8ZWwbyCa0IQvpv) is giving me trouble when attempting to simply create a PdfFileReader object

Code:
```
with open('./media/NTB - LOI.pdf', 'rb') as input:
  PyPDF2.PdfFileReader(input)
```

Error:

```
Traceback (most recent call last):
  File "<console>", line 2, in <module>
  File "/home/vershimaajo/gigarbox_academia/venv/lib/python3.6/site-packages/PyPDF2/pdf.py", line 1084, in __init__
    self.read(stream)
  File "/home/vershimaajo/gigarbox_academia/venv/lib/python3.6/site-packages/PyPDF2/pdf.py", line 1883, in read
    stream.seek(-11, 1)
OSError: [Errno 22] Invalid argument
```

Thanks for assistance!

### Additional contract requirements

- `PyPDF2.PdfFileReader` is constructed from a binary file-like object containing PDF data, and accepts an optional boolean `strict` keyword argument.
- When `strict=True` and the PDF trailer contains a `/Prev 0` entry, constructing the reader raises `PyPDF2.pdf.utils.PdfReadError`.
- When `strict=False`, a `/Prev 0` entry in the trailer is tolerated and the reader is constructed successfully.
