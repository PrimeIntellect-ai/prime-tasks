removing beginning `s` in text/html, with `<style />`
moved here from: https://github.com/sveltejs/language-tools/issues/324

<!-- Before you submit a bug, please make sure that:
- you don't have   "files.associations": {"*.svelte": "html"  }   inside your VSCode settings (if you can't remember ever doing that, you don't have that)
- you are using Svelte for Vscode (NOT the old "Svelte" by James Birtles) and have disabled all other Svelte-related extensions to reproduce the bug
- if it's a preprocessor related bug like "can't use typescript", did you setup `svelte-preprocess` and/or `svelte.config.js`? See the docs for more info.
-->

**Describe the bug**
This or `prettier`, is removing starting works with beginning `s`, like `sweet`, `Sweet`, `sssweet`, after saving.

**To Reproduce**
Steps to reproduce the behavior:

`App.svelte`
```
<style>

</style>

sssweet
```

get's turned into: (after saving, see screenshot)

```
<style>

</style>

weet
```

**Expected behavior**
It should keep the `sssweet`

**Screenshots**
![2020-07-19_21-20-22](https://user-images.githubusercontent.com/1171187/87890977-7f258000-ca06-11ea-8c0e-ccb0bb71cdbd.gif)


**System (please complete the following information):**
 - OS: Windows 10
 - IDE: VSCode
 - Plugin/Package: "Svelte for VSCode", "Prettier"

**Additional context**
Strange.
