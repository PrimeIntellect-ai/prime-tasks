Version pdfminer.six 20191107 incorrectly orders some text
Upgrading from version 20181108 to 20191107 pdfminer parses some words out of order.
In version 20181108 the ordering was correct, see first output below.
In version 20191107 the ordering is incorrect, see second output below.

In this pdf: http://unec.edu.az/application/uploads/2014/12/pdf-sample.pdf

The fourth bullet point ends with the word "anyone".  When parsing, "anyone" now ends up at the end of the third bullet point instead (directly following "incompatibilities").

Sample parsing logic:
```
import os
import sys
from io import StringIO
from pprint import pprint

from pdfminer.pdfparser import PDFParser
from pdfminer.pdfdocument import PDFDocument
from pdfminer.pdfpage import PDFPage, PDFTextExtractionNotAllowed
from pdfminer.pdfinterp import PDFResourceManager, PDFPageInterpreter
from pdfminer.layout import LAParams
from pdfminer.converter import TextConverter

def get_text(path):
    fd = open(path, 'rb')

    parser = PDFParser(fd)
    document = PDFDocument(parser)

    # Try to parse the document
    if not document.is_extractable:
        raise PDFTextExtractionNotAllowed

    rsrcmgr = PDFResourceManager()

    text = StringIO()

    device = TextConverter(rsrcmgr, text, codec='utf-8', laparams=LAParams())

    interpreter = PDFPageInterpreter(rsrcmgr, device)

    for page in PDFPage.create_pages(document):
        interpreter.process_page(page)

    return text.getvalue()

txt = get_text(os.path.abspath(sys.argv[1]))
pprint(txt)
```
### 20181108  output
```
$ python testit.py pdf-sample.pdf
('Adobe Acrobat PDF Files\n'
 '\n'
 'Adobe® Portable Document Format (PDF) is a universal file format that '
 'preserves all\n'
 'of the fonts, formatting, colours and graphics of any source document, '
 'regardless of\n'
 'the application and platform used to create it.\n'
 '\n'
 'Adobe PDF is an ideal format for electronic document distribution as it '
 'overcomes the\n'
 'problems commonly encountered with electronic file sharing.\n'
 '\n'
 '•  Anyone, anywhere can open a PDF file. All you need is the free Adobe '
 'Acrobat\n'
 "Reader. Recipients of other file formats sometimes can't open files because "
 'they\n'
 "don't have the applications used to create the documents.\n"
 '\n'
 '•  PDF files always print correctly on any printing device.\n'
 '\n'
 '•  PDF  files  always  display  exactly  as  created,  regardless  of  '
 'fonts,  software,  and\n'
 'operating systems. Fonts, and graphics are not lost due to platform, '
 'software, and\n'
 'version incompatibilities.\n'
 '\n'
 '•  The  free  Acrobat  Reader  is  easy  to  download  and  can  be  freely  '
 'distributed  by\n'
 '\n'
 'anyone.\n'
 '\n'
 '•  Compact  PDF  files  are  smaller  than  their  source  files  and  '
 'download  a\n'
 '\n'
 'page at a time for fast display on the Web.\n'
 '\n'
 '\x0c')
```

### 20191107 output
```
$ python testit.py pdf-sample.pdf
('Adobe Acrobat PDF Files\n'
 '\n'
 'Adobe® Portable Document Format (PDF) is a universal file format that '
 'preserves all\n'
 'of the fonts, formatting, colours and graphics of any source document, '
 'regardless of\n'
 'the application and platform used to create it.\n'
 '\n'
 'Adobe PDF is an ideal format for electronic document distribution as it '
 'overcomes the\n'
 'problems commonly encountered with electronic file sharing.\n'
 '\n'
 '•  Anyone, anywhere can open a PDF file. All you need is the free Adobe '
 'Acrobat\n'
 "Reader. Recipients of other file formats sometimes can't open files because "
 'they\n'
 "don't have the applications used to create the documents.\n"
 '\n'
 '•  PDF files always print correctly on any printing device.\n'
 '\n'
 '•  PDF  files  always  display  exactly  as  created,  regardless  of  '
 'fonts,  software,  and\n'
 'operating systems. Fonts, and graphics are not lost due to platform, '
 'software, and\n'
 'version incompatibilities.\n'
 '\n'
 'anyone.\n'
 '\n'
 '•  The  free  Acrobat  Reader  is  easy  to  download  and  can  be  freely  '
 'distributed  by\n'
 '\n'
 '•  Compact  PDF  files  are  smaller  than  their  source  files  and  '
 'download  a\n'
 '\n'
 'page at a time for fast display on the Web.\n'
 '\n'
 '\x0c')
```
