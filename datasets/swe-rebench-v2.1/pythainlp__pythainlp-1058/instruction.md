Thai character splitter to display cell
## Detailed description

This feature will split Thai text to display cell. E.g. แม่น้ำอยู่ที่ไหน -> แ ม่ น้ํ า อ ยู่ ที่ ไ ห น.

It will split Thai text to character but It doesn't split tone marks.

### Additional contract requirements

- Add a public function `display_cell_tokenize(text: str) -> List[str]` in the `pythainlp.tokenize` module, importable as `from pythainlp.tokenize import display_cell_tokenize`.
- The function returns an ordered list of display-cell strings for the given Thai text.
- Tone marks are kept together with their base characters rather than being split into separate cells.
- A display cell consists of a base character together with any Thai combining marks (tone marks and vowel signs) that immediately follow it. The character ำ (sara am) is represented as two display cells: ํ (nikhahit) followed by า (sara aa).
- The function returns an empty list when the input is empty.
- The function returns an empty list when the input is not a string.
