Remove thin spaces between Japanese segments and brackets
日本語と全角括弧類との間に発生する四分アキを取り除く。

`LanguageClass.isJapanese()` で、
一部括弧類が日本語に判定されないことに起因しているので、
[HIDDEN]

## 現状
**入力**
```
どうも（こんにちは］
```

**出力**
```
どうも<thin-space />（<thin-space />こんにちは<thin-space />］
```

## 修正後
**入力**
```
どうも（こんにちは］
```

**出力**
```
どうも<thin-space />（こんにちは］
```

### Additional contract requirements

- 日本語の文字の直後に全角の閉じ括弧が続く場合、および全角の開き括弧の直後に日本語の文字が続く場合、その間に四分アキを挿入しない。
