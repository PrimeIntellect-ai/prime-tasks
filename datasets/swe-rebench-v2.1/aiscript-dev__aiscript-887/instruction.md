複数行コメントの途中でEOFになってもエラーにならない
以下のように、複数行コメントの途中でEOFとなるコードが文法エラーにならない。
```js
/* comment
```

ただし、EOFの直前が`*`である場合は、「end of stream」エラーが出る。
```js
/* *
```

### Additional contract requirements

- 複数行コメント（`/*` で始まり `*/` で閉じられるコメント）が `*/` で閉じられる前にソースの末尾（EOF）に達した場合、パーサーは `AiScriptUnexpectedEOFError` を投げる。
- この挙動は EOF の直前の文字が `*` であるかどうかに依存しない。`/* comment` のように `*` で終わらない場合も、`/* *` のように `*` で終わる場合も、どちらも `AiScriptUnexpectedEOFError` を投げる。
