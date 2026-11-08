Add support for Text-Rendering-Mode 3 (invisible)
> As a user of the library I want to be able to open an existing PDF containing scanned images and add text to it generated through the Google Vision API. I do get coordinates and detected sniplets of text. In order to improve the search-ability of the PDF I want to add the plain text to the PDF while the user shall not see the added text but the original scanned image. Though they should be able to copy "the scanned text" after the OCR.

That's where the "invisible" (no stroke, no fill) text rendering mode comes in handy: The user will not have a visible text but is able to copy it as it is just not "decorated" with color.

### Additional contract requirements

- `TextStyle` has an integer field named `RenderingMode` holding the PDF text rendering mode. Setting it to `3` makes the chunks that use that style render as invisible text.
- Text drawn with rendering mode 3 must not paint visible glyphs in the generated PDF page, and must remain available as text for copying or text extraction.
