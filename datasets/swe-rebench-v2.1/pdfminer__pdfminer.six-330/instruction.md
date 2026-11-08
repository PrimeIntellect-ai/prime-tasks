Create function that returns the extracted text
Currently, you need to use an file-like output argument to get the text from a pdf. For example:

```python
from io import StringIO
output_string = StringIO()
with open('samples/simple1.pdf', 'rb') as fin:
     extract_text_to_fp(fin, output_string)
```

Having to use an output-argument is annoying since most people just want to do:

```python
text = pdf_to_text('samples/simple1.pdf')
```

### Additional contract requirements

The convenience function is available as `pdfminer.high_level.extract_text`. The `pdf_to_text` spelling in the example describes the desired convenience operation; callers use the function name provided by the public module API.
