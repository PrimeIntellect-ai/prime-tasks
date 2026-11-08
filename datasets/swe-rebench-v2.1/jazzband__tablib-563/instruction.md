Databook unable to load xls
I'm trying to load an xls file however it fails with the following error
```
with open("xls_file", "rb") as fh:
    imported_data = Databook().load(fh, "xls")
```
```
Traceback (most recent call last):
  File ".\test.py", line 5, in <module>
    imported_data = Databook().load(fh, "xls")
  File "lib\site-packages\tablib\core.py", line 872, in load
    fmt.import_book(self, stream, **kwargs)
  File "lib\site-packages\tablib\formats\_xls.py", line 103, in import_book
    xls_book = xlrd.open_workbook(file_contents=in_stream)
  File "lib\site-packages\xlrd\__init__.py", line 166, in open_workbook
    file_format = inspect_format(filename, file_contents)
  File "lib\site-packages\xlrd\__init__.py", line 57, in inspect_format
    peek = content[:PEEK_SIZE]
TypeError: '_io.BufferedReader' object is not subscriptable
```
