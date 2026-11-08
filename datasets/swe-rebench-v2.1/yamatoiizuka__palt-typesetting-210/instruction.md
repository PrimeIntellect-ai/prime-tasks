Remove thin spaces between Latin punctuation and Japanese segment
日本語と半角カンマ、ピリオドとの間に発生する四分アキを取り除く

## 現状
**入力**
```
ラテン, 日本語.
```

**出力**
```
ラテン<thin-space />, 日本語<thin-space />.
```

## 修正後
thin space が挿入されず、そのままのスペースを維持するように修正します。
**入力**
```
ラテン, 日本語.
```

**出力**
```
ラテン, 日本語.
```
