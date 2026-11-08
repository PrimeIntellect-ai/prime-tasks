Column header
# Summary of your issue

I am extracting data from a table using the "guess=True" option. Unfortunately, the first row is imported as column header. (The guess is not really wrong, since the typeface is bold and there is a line below it, see [Example](https://esv.ch/documents/ranglisten/2017-06-05_12_Schwingertag_Laupen-ST.pdf).) I didn't find I way to tell read_pdf_table not to treat the particular first line as column header.

Would it be possible to add a "header=None" option?
