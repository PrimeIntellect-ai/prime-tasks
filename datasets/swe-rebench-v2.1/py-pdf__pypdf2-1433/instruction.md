AttributeError: 'NameObject' object has no attribute 'get_data' when running extract_text on page of pdf
While extracting text from the pages of a pdf using the extract_text method, an unexpected AttributeError was raised.
So far I have observed this happening with only one specific pdf.

## Environment

Which environment were you using when you encountered the problem?

```bash
$ python -m platform
Windows-10-10.0.22621-SP0

$ python --version
Python 3.10.4

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
2.11.1
```

## Code + PDF

This is a minimal, complete example that shows the issue:

```python
from PyPDF2 import PdfReader

pdf = PdfReader('./Thesis_MJ_Morshed_Chowdhury.pdf')
for i, page in enumerate(pdf.pages):
    print(i, page.extract_text())
```

The error only occurs with this pdf: https://comserv.cs.ut.ee/home/files/Thesis_MJ_Morshed_Chowdhury.pdf?study=ATILoputoo&reference=CE3D449743B31F757F4BB5CC21FAA958495487AF

The pdf is from a public thesis database of the University of Tartu, but given that it has no license allowing it to be redistributed by third parties I suspect that adding this as a test case would not be allowed.

## Traceback

This is the complete Traceback I see:

```
Traceback (most recent call last):
  File "<redacted>\test.py", line 5, in <module>
    print(i, page.extract_text())
  File "<redacted>\lib\site-packages\PyPDF2\_page.py", line 1823, in extract_text
    return self._extract_text(
  File "<redacted>\lib\site-packages\PyPDF2\_page.py", line 1323, in _extract_text
    cmaps[f] = build_char_map(f, space_width, obj)
  File "<redacted>\lib\site-packages\PyPDF2\_cmap.py", line 28, in build_char_map
    map_dict, space_code, int_entry = parse_to_unicode(ft, space_code)
  File "<redacted>\lib\site-packages\PyPDF2\_cmap.py", line 194, in parse_to_unicode
    cm = prepare_cm(ft)
  File "<redacted>\lib\site-packages\PyPDF2\_cmap.py", line 207, in prepare_cm
    cm: bytes = cast(DecodedStreamObject, ft["/ToUnicode"]).get_data()
AttributeError: 'NameObject' object has no attribute 'get_data'
```
