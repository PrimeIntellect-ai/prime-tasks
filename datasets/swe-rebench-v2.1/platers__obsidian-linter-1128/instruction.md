Bug: Remove space header when option `RemoveSpaceAroundCharacters` is enabled and Katakata is beginning of the line
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Title.

## How to Reproduce

1. Enable `RemoveSpaceAroundCharacters` and `includeCJKSymbolsAndPunctuation` in the settings
2. Create a note with the following content:

```
## テスト
```

3. Lint the note, then the space between `##` and `テスト` will be removed.

## Expected Behavior

Don't remove the space between `##` and `テスト`.

## Device

- [ ] Desktop
- [x] Mobile


<!-- 新しいイシューの本文を編集し、エディターの右上にある ✓ [イシューの作成] ボタンをクリックします。最初の行がイシューのタイトルになります。担当者とラベルは空白行の後に続きます。イシューの本文を開始する前に空の行を残します。 -->
