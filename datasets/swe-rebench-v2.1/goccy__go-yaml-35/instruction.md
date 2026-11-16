not parsed after newline in block string
複数行文字列を単体でパースしようと思うと、二行目以降が切り捨てられてしまうようです。

https://play.golang.org/p/iHIxeMMDhT5

親構造体で `UnmarshalYAML`を定義していて、文字列のフィールドを個別にUnmarshal()する必要がある場合に問題がおきました。
