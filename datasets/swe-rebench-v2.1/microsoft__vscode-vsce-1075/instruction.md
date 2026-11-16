The following include patterns in the...
Hello. I was working on version 2 (I am unable to specify which exact one), and everything was fine. Then I updated to the latest version 2, and I [encountered an error] when packing an extension. I decided to switch to the third version, but the error remained. Please take a look, it seems to be a bug.

```sh
vsce package --no-dependencies
```

```txt
 ERROR  The following include patterns in the "files" property in package.json do not match any files packaged in the extension:
  - /Users/vanyauhalin/self/moondusttheme/README.md
Remove any include pattern which is not needed.
```

```sh
cat package.json | jq '.files'
```

```json
[
  "dist/dark.json",
  "dist/light.json",
  "docs/icon.png",
  "LICENSE",
  "package.json",
  "README.md"
]
```

```sh
vsce package --no-dependencies --allow-unused-files-pattern
```

```txt
 INFO  Files included in the VSIX:
moondusttheme-0.7.0.vsix
├─ [Content_Types].xml
├─ extension.vsixmanifest
└─ extension/
   ├─ LICENSE.txt [1.07 KB]
   ├─ package.json [1.66 KB]
   ├─ readme.md [0.12 KB]
   ├─ dist/
   │  ├─ dark.json [135.73 KB]
   │  └─ light.json [135.93 KB]
   └─ docs/
      └─ icon.png [15.8 KB]

 DONE  Packaged: /Users/vanyauhalin/self/moondusttheme/moondusttheme-0.7.0.vsix (8 files, 42.98 KB)
```

[encountered an error]: https://github.com/vanyauhalin/moondusttheme/actions/runs/11644911121/job/32427342940/
