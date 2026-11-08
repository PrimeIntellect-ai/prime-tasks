Support for text containing semicolons
Currently it isn't possible, as far as I know, to use semicolons in the lines parameter as text since it will be always be treated as a line separator.

Current workarounds include using a [Greek Question Mark `;`](https://www.fileformat.info/info/unicode/char/037e/index.htm) in place of the semicolon in your text.

## Possible ideas for solutions

**Option 1:** Allow specifying the separator character as another parameter (eg. `&sep=|`) to change which character is used for separation and allowing semicolons. On the demo site this can be hidden from the user and just use `;` if no semicolons are used in the text, and something else if there are (Possibly the separator could become `;;` if `;` appears in the text, `;;;` if `;;` appears in the text, etc. to allow for infinitely many possible separators depending on the text.)

**Option 2:** Allow a way of "escaping" semicolons (eg. `\;`) in the text which should get treated as text on the backend instead of as a separator. (Note may be a breaking change since it changes the way a line ending with a backslash is parsed.)

**Option 3:** Automatically convert semicolons in the text on the demo site to Greek Question Marks instead of making a backend solution. (This is not ideal since it doesn't provide an easy solution for those not using the demo site.)

I think **Option 1** would be the cleanest solution, I am open to other ideas if anyone has input on the subject.

### Additional contract requirements

When the lines input contains semicolons that are text rather than line breaks, callers can provide a non-empty `separator` rendering option to identify the boundary between lines. Semicolon-delimited input remains the default when this option is omitted. The chosen delimiter separates lines, while semicolons that are not part of that delimiter remain in the rendered line text.
