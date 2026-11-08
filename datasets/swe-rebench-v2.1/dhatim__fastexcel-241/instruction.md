Default font name / size
Is it possible to set a default font name and size using fastexcel? If so, how?

I've tried to use `sheet.range()` over the entire document, however this seems to drastically increase the document size.

### Additional contract requirements

Provide `Workbook.setGlobalDefaultFont(String fontName, double fontSize)` to set the workbook’s default font name and size. Cells without an explicitly assigned font use this configured default. This workbook-level setting applies without requiring a range covering the document.
