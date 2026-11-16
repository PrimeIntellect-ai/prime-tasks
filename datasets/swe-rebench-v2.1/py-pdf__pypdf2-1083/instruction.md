Add font information to PdfReader instance
It would be a nice enhancement to include information on what fonts are contained in a pdf and whether or not they are embedded. I believe I have the code that does it, but after looking over the code base, there is probably a smarter way to go about it.

Here is a gist link:
https://gist.github.com/tiarno/8a2995e70cee42f01e79

### Additional contract requirements

When examining pages obtained from a `PdfReader`, callers can determine the font names present on each page and distinguish names for embedded fonts from names for unembedded fonts. The results must reflect the document being read, not just a fixed collection of known PDFs.

The font information is exposed on each page object through a method named `_get_fonts()` that takes no arguments and returns a tuple of two sets of font names: the first set holds the names of embedded fonts, the second holds the names of unembedded fonts. Names are reported as they appear in the document's font dictionaries (for example `/Helvetica`).
