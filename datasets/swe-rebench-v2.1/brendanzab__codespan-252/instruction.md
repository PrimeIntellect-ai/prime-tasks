Fix tabulation columns in diagnostic output
Currently codespan-reporting treats tabs as being a constant width, but this is incorrect, as @legendiguess [notes](https://github.com/rust-lang/annotate-snippets-rs/issues/25#issuecomment-604805594):

> > The other would be to only adjust the underline calculation to account for tabs in line, but I'm not sure if display of `"\tt"` is always 5 ascii characters.
>
> `\t` move next characters to the next tabulation column. so basically it's adds from 1 to 4 ascii characters, dependent on caret position off last tabulation column

We'll need to change the [source writer](https://github.com/brendanzab/codespan/blob/a77e646944765dfb338185b0ba9504500afb7304/[HIDDEN]) and the [width calculuation](https://github.com/brendanzab/codespan/blob/a77e646944765dfb338185b0ba9504500afb7304/[HIDDEN]) to properly support tabulation columns.

### Additional contract requirements

- In rendered source, a tab advances to the next tabulation stop according to the configured tab width; its displayed width depends on the current column rather than being constant.
- Diagnostic underlines and carets must align with the corresponding source characters when tabs occur before or within a labeled range.
