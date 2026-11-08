HTML comment is duplicated when using Format on Save
When enabling "Format on Save" in VS Code settings, recently I've noticed that some comments are being duplicated on save. Here are two images:

Before:
![Screen Shot 2021-02-14 at 9 42 46 AM](https://user-images.githubusercontent.com/51680874/107887318-5cc6e880-6ea9-11eb-8318-4d40408bc00a.png)

After:
![Screen Shot 2021-02-14 at 9 43 00 AM](https://user-images.githubusercontent.com/51680874/107887320-618b9c80-6ea9-11eb-83c5-f198c221c051.png)

I didn't have this issue before and I can only prevent it by disabling "Format on Save" or unchecking "Format: Enable" in Settings under Extensions > Svelte.

<!-- Before you submit a bug, please make sure that:
- you have searched and found no existing open issue with the problem at hand
- you don't have   "files.associations": {"*.svelte": "html"  }   inside your VSCode settings (if you can't remember ever doing that, you don't have that)
- you are using Svelte for Vscode (NOT the old "Svelte" by James Birtles) and have disabled all other Svelte-related extensions to reproduce the bug
- if it's a preprocessor related bug like "can't use typescript", did you setup `svelte-preprocess` and/or `svelte.config.js`? See the docs for more info.
-->
