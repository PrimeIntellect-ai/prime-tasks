Some forms with escaped newlines crash Enketo
Following https://github.com/XLSForm/pyxform/pull/768, we've had reports of two forms that don't load correctly in Enketo. One errors on launch, the other has a select in which all choices are displayed without labels.

The issue has to do with escaped newlines because that's the only escaped character the forms contain. We've asked for the form source to try to find the root cause.

Escaped newlines work fine in Enketo, Collect, ODK Web Forms for everything I've tried so far: [multiline-attributes.xlsx](https://github.com/user-attachments/files/20684831/multiline-attributes.xlsx)

### Additional contract requirements

- For a `root` node whose text and `attr` value are `' " & < > \r \n \t`, XML serialization with `toprettyxml(indent="", newl="")` must equal `<root attr="' &quot; &amp; &lt; &gt; \r \n \t">' " &amp; &lt; &gt; \r \n \t</root>`; here `\r`, `\n`, and `\t` denote carriage return, newline, and tab characters.

Forms exported from XLSForms with line breaks in a choice filter must retain those literal line breaks in the generated XForm attribute value, and the generated choices must retain their labels.
