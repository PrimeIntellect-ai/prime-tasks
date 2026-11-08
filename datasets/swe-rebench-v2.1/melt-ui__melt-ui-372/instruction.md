🐛Bug: multi-select doesn't correctly set `data-selected` or `aria-selected`
**Describe the bug**
When `multiple` is set to `true`, `$isSelected` works properly, but `data-selected` and `aria-selected` don't get set properly.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to the [Melt UI Select docs](https://www.melt-ui.com/docs/builders/select)
2. Scroll down to the Multi-Select example
3. Select any option and inspect the option, observe that `data-selected` is not present and that `aria-selected` is set to `false`.

**Expected behavior**
`data-selected` should exist and `aria-selected` should be set to `true`

**Screenshots**
![image](https://github.com/melt-ui/melt-ui/assets/13283469/e39577b0-0591-432f-baa9-3302644f1a7d)


**Desktop (please complete the following information):**
 - OS: MacOS
 - Browser: Brave
 - Version: [Version 1.56.20 Chromium: 115.0.5790.171 (Official Build) (arm64)](https://brave.com/latest/)
