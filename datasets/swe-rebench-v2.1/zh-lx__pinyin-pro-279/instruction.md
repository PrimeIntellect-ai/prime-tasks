first isn't consistent
## bug 描述

first 在 `pattern: 'first'` 和 `type: 'all'` 中表现不一致：
- `pattern: 'first'` 中无论是否中文，都返回结果第一个字符
- `type: 'all'`: 是中文则返回结果第一个字符，非中文返回空字符串

## 你预期的样子是？

是中文则返回结果第一个字符，非中文返回非中文字符串

## pinyin-pro 版本号

`3.25.0`

### Additional contract requirements

- With `pattern: 'first'`, a Chinese character contributes its first pinyin letter, and a non-Chinese token contributes its full original text. For example, `pinyin('赵a𧒽', { pattern: 'first' })` returns `z a 𧒽`.
- With `type: 'all'`, the `first` field of a Chinese character is its first pinyin letter, and the `first` field of a non-Chinese token is that token's full original text (for example `a` gives `"a"` and `𧒽` gives `"𧒽"`).
