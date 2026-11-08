git patch with empty emails causing  parse errors
I have a git patch that is triggering this line https://github.com/bluekeyes/go-gitdiff/blob/13e8639a0b49cb49741b05f11ac52c530d2d38f0/gitdiff/patch_header.go#L114


```
commit 44b179bf547c84cb588480558de71df1e9243aaf
Author: bot-deploy Github Action <>
Date:   Tue Mar 5 17:07:58 2024 +0000

    Export updated bot artifact

diff --git a/bot_exports/ba3e9571-b1d9-45cb-be06-a7b4a2e279e7.blob b/bot_exports/ba3e9571-b1d9-45cb-be06-a7b4a2e279e7.blob
index 4ea75f9..f92448c 100644
Binary files a/bot_exports/ba3e9571-b1d9-45cb-be06-a7b4a2e279e7.blob and b/bot_exports/ba3e9571-b1d9-45cb-be06-a7b4a2e279e7.blob differ
```

`Author: bot-deploy Github Action <>` is causing parsing to fail. Can this be gracefully handled, like returning an empty email?
