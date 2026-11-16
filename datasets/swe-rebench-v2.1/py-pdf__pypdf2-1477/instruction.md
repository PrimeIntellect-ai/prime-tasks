ValueError: read length must be non-negative or -1
Replace this: What happened? What were you trying to achieve?

## Environment

Which environment were you using when you encountered the problem?

```bash
$ python -m platform

macOS-10.16-x86_64-i386-64bit

$ python -c "import PyPDF2;print(PyPDF2.__version__)"

```
2.11.2

## Code + PDF

This is a minimal, complete example that shows the issue:

```python

def write_public(pdf_name, output_folders):
    split_names = gen_split_names(pdf_name)
    input_pdf = PdfFileReader(open(pdf_name, "rb"))
    num_partitions = len(output_folders)
    for num_person in range(len(split_names)):
        if num_person == len(split_names) - 1:
            end = input_pdf.numPages
        else:
            end = split_names[num_person+1][0]
        output = PdfFileWriter()
        for page_num in range(split_names[num_person][0], end):
            output.addPage(input_pdf.getPage(page_num))
        with open(output_folders[num_person % num_partitions] + "/" + split_names[num_person][1][0]+split_names[num_person][1][
            1]+".pdf",
                  "wb") as outstream:
            output.write(outstream)
```
Share here the PDF file(s) that cause the issue. The smaller they are, the
better. Let us know if we may add them to our tests!

I (legally) can't share the PDF, but I can say that I ran this code on some 240 pdfs, and it broke on only this one pdf. The only thing I find different about this pdf is a bunch of math equations in LaTeX. Please feel free to close this issue, I understand non reproducible bug reports aren't exactly useful, but figured I'd give it a shot.

## Traceback

This is the complete Traceback I see:
File "/Users/tynanseltzer/test2/splitter.py", line 135, in <module>
    write_public(PUBLIC_PDF, fls)
  File "/Users/tynanseltzer/test2/splitter.py", line 64, in write_public
    output.write(outstream)
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/_writer.py", line 832, in write
    self.write_stream(stream)
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/_writer.py", line 805, in write_stream
    self._sweep_indirect_references(self._root)
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/_writer.py", line 954, in _sweep_indirect_references
    data = self._resolve_indirect_object(data)
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/_writer.py", line 999, in _resolve_indirect_object
    real_obj = data.pdf.get_object(data)
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/_reader.py", line 1222, in get_object
    retval = read_object(self.stream, self)  # type: ignore
  File "/Users/tynanseltzer/anaconda3/lib/python3.9/site-packages/PyPDF2/generic/_data_structures.py", line 872, in read_object
    [HIDDEN]
ValueError: read length must be non-negative or -1

### Additional contract requirements

When object parsing encounters malformed input at the start of an elementary object, it must report the problem through its normal PDF parsing error path, rather than raising a `ValueError` due to an invalid read length.
