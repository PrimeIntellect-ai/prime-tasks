Woorkbook Subject/Title
Is it possible to set the title of an Excel file? That is, the title that can then be queried in the programme under Information.

### Additional contract requirements

A workbook must expose its associated mutable document-properties object through `Workbook.properties()`. The returned object must provide `setTitle(String)` so callers can set the document title.
