KeyError: '/Annots' in update_page_form_field_values
I'm filling a PDF file with the update_page_form_field_values method but if the PDF file contains at least one page without a field a KeyError was thrown.

## Environment

Which environment were you using when you encountered the problem?

```bash
$ python -m platform
Linux-5.10.104-linuxkit-x86_64-with-glibc2.31

$ python -c "import PyPDF2;print(PyPDF2.__version__)"
2.10.6
```

## Code + PDF

This is a minimal, complete example that shows the issue:

```python
for idx, page in enumerate(reader.pages):
            writer.add_page(page)
            writer.update_page_form_field_values(
                writer.get_page(idx), self.data, FieldFlag.READ_ONLY
            )
```

## Traceback

```
File "/app/.venv/lib/python3.10/site-packages/PyPDF2/_writer.py", line 625, in update_page_form_field_values
for j in range(len(page[PG.ANNOTS])):  # type: ignore
File "/app/.venv/lib/python3.10/site-packages/PyPDF2/generic/_data_structures.py", line 149, in __getitem__
return dict.__getitem__(self, key).get_object()
KeyError: '/Annots'
```
