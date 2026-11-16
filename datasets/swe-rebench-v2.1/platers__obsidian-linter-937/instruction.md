Bug: no bare URL will contain some illegal characters
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

I am a Chinese language speaker and I want to directly follow Chinese characters after URLs, but I will include these Chinese characters

## How to Reproduce

original sentence
```
我是一个网址https://github.com/platers/obsidian-linter一些中文字符。被包含进去了
```
After pressing ctrl+s to format
```
我是一个网址<https://github.com/platers/obsidian-linter一些中文字符。被包含进去了>
```
If I continue to add
```
我是一个网址<https://github.com/platers/obsidian-linter一些中文字符。被包含进去了>如果我继续写
```
Press ctrl+s again
```
我是一个网址<<https://github.com/platers/obsidian-linter一些中文字符。被包含进去了>如果我继续写>
```

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

V1.19.1 does not meet this issue, V1.20.0 meet this issue
