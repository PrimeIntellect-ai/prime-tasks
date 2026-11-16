[BUG] - [AttributedText] - Character lookup logic is wrong
`AttributedText` supports looking up characters and placeholders by index. The implementation is wrong for character lookup. It pulls characters from the plain text, not the text with placeholders, which can lead to the wrong characters being returned, and exceptions trying to access indices beyond the end of the text string.
