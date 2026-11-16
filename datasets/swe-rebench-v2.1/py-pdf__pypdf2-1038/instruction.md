Allow specifying the PDF file version
PyPDF2 currently writes to v1.3 (Acrobat 4.x). Is it possible to allow saving to other versions?

We recently used the library to combine several thousands of pages into file sets (of engineering drawings). Each of the individual filenames (pages) were used as bookmarks in the set. I have found that I cannot use Acrobat X to insert or replace a page manually afterwards because it messes up the bookmarks. If I save the modified PDF using the optimized pdf option (where I can specify the version I want and in this case it would be 1.3) the bookmarks are deleted.

Before:
![image](https://cloud.githubusercontent.com/assets/3391494/5396744/89e987bc-8122-11e4-90c0-4c53dd5468bd.png)

Save as
![image](https://cloud.githubusercontent.com/assets/3391494/5396753/a64532d0-8122-11e4-8099-e68e7a2fc514.png)

After:
![image](https://cloud.githubusercontent.com/assets/3391494/5396767/b523633a-8122-11e4-8be8-6810701b4d36.png)

### Additional contract requirements

- `PdfWriter` (in `PyPDF2._writer`) exposes a public `pdf_header` property. Reading it returns the PDF version header as `bytes` (for example `b"%PDF-1.3"`) that will be written to the output file; it initially reflects the writer's base version. Assigning a `bytes` header to it sets the version that is written to the output file.
- Adding pages from other PDFs automatically promotes the writer's header to the highest version required by the added content.
- `PyPDF2._utils` exposes a function `_get_max_pdf_version_header(header1: bytes, header2: bytes) -> bytes` that returns the higher of the two supplied supported PDF version headers. If neither argument is a supported header, it raises `ValueError` with the message `neither {header1!r} nor {header2!r} are proper headers`.
