Font kerning / character spacing
Hello I'm currently evaluating unidoc for PDF generation purposes.

I need to be able to set character spacing (also known as kerning) for some paragraphs.
Is that currently possible? I haven't found anything in the API or the examples.

Thanks for any pointers!

### Additional contract requirements

- `TextStyle.CharSpacing` is a `float64` field.
- The value represents additional character spacing expressed in 1/1000 text space units.
- When a styled paragraph chunk is drawn with a non-zero `CharSpacing`, the value is emitted through the PDF `Tc` operator during drawing; the operand passed to `Tc` equals the `CharSpacing` value (the field value is emitted directly, without additional scaling).
