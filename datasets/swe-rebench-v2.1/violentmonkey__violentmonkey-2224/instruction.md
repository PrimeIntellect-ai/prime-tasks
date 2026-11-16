[BUG] UserScripts localization for zh-* broken on Firefox Android
<!-- Please search the existing issues first as the problem may be already reported.
     Please verify the bug is not fixed in the latest beta:
     https://github.com/violentmonkey/violentmonkey/releases -->

### Sequence of actions: <!-- e.g. install userscript, open example.com, click page -->
1.
2.
3.

### Problem: <!-- e.g. error in devtools console -->

Firefox for Android, weirdly, uses "zh-Hant-TW" instead of "zh-TW" as the language code for Traditional Chinese (Taiwan), which breaks the function (see below) used to get localized metadata since most (if not all) of the scripts use the code "zh-TW". Same should happen on Simplified Chinese (zh-CN, zh-Hans-CN).

https://github.com/violentmonkey/violentmonkey/blob/5eb2c5ad8de7ad5df6ac081e4167e715f02c6056/src/common/index.js#L159

### Expected result:  <!-- e.g. "ok" in console or some button appears -->

[HIDDEN]

#### Devtools console contents:

N/A

#### Environment:
- OS: Android 14
- Browser: Firefox Nightly for Android 124.0a1 <!-- specify the real version -->
- Violentmonkey Version: 2.18.0

### Additional contract requirements

When the browser's preferred languages include `zh-Hant-TW`, Traditional Chinese (Taiwan) metadata localized as `zh-TW` should be selected. When they include `zh-Hans-CN`, Simplified Chinese metadata localized as `zh-CN` should be selected. Selection should respect the user's preferred-language order. If no preferred language matches a localized value, use the unlocalized metadata value, or an empty string when it is absent.
