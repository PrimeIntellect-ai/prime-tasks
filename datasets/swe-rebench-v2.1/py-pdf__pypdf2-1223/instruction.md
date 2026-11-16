Stream has ended unexpectedly
[out.pdf](https://github.com/mstamy2/PyPDF2/files/2379430/out.pdf)

```
"PyPDF2/generic.py", line 334, in readStringFromStream
    raise PdfStreamError("Stream has ended unexpectedly")
PyPDF2.utils.PdfStreamError: Stream has ended unexpectedly
```

with this code:

```python
import StringIO
from PyPDF2 import PdfFileWriter, PdfFileReader
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4

input_pdf = '../out.pdf'

ifh = file(input_pdf, 'rb')
inv_input = PdfFileReader(ifh, strict=False)

packet = StringIO.StringIO()

can = canvas.Canvas(packet, pagesize=A4)
can.drawString(10, 10, 'ADDED INFO')
can.save()

packet.seek(0)
added_info = PdfFileReader(packet)

output = PdfFileWriter()

page_count = 1
for x in range(page_count):
    page = inv_input.getPage(x)
    page.mergePage(added_info.getPage(0))
    output.addPage(page)

file_stream = file('../pypdf.pdf', 'wb')
output.write(file_stream)
file_stream.close()
```

### Additional contract requirements

- Consecutive octal escapes in a PDF string must each decode to their corresponding byte.
- When a PDF string contains an octal escape followed by a non-octal byte, decoding the escape must leave that byte available for normal parsing as the following string content or delimiter.
- A PDF page whose content contains an octal escape immediately before the string-closing parenthesis can be read and merged with another page without raising an unexpected-stream-end error.
