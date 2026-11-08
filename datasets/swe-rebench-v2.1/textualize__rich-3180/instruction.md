[BUG] Chunks of text go missing when writing Asian text (wrapping issue)
### Description

(Originally reported in Textual: https://github.com/Textualize/textual/issues/3567)

When you print Asian text (specifically Chinese and Japanese, which do not use spaces), portions of the text go missing, making it unreadable.

This seems to be related to wrapping, as the characters which go missing are at the end of a line.
Instead of being wrapped on to a new line, they disappear.

There are [rules for wrapping](https://en.m.wikipedia.org/wiki/Line_breaking_rules_in_East_Asian_languages) in these languages which would take more effort to adhere to, but at the very least, text should not go missing when printed.

### Examples

For example, running the snippet below, the `7` in `1670` disappears:

```python
from rich.console import Console
console = Console(width=20)
console.print("アプリケーションは1670万色を使用でき")
```

Output:

```
アプリケーションは16
0万色を使用でき
```

And in many cases, like those reported in this issue, multiple characters disappear:

```python
from rich.console import Console
console = Console(width=20)
console.print("TextualはPythonの高速アプリケーション開発フレームワークです")
```

Output:

```
TextualはPy
thonの高速アプリ
ケーション開発フレー
```

Notice that many of the characters at the end of the text are completely missing (`ムワークです`).

### Additional contract requirements

- Add a public function `chop_cells(text: str, width: int) -> list[str]` in module `rich.cells`. It splits `text` into lines that each occupy at most `width` display cells, counting double-width characters as two cells, without losing any input characters. If a character is wider than `width`, return it on a line by itself; that line may exceed `width`.
- Specifically, `chop_cells("abcdefghijk", 3)` must return `["abc", "def", "ghi", "jk"]`, `chop_cells("ありがとう", 3)` must return `["あ", "り", "が", "と", "う"]`, and `chop_cells("あ1り234が5と6う78", 3)` must return `["あ1", "り2", "34", "が5", "と6", "う7", "8"]`.
