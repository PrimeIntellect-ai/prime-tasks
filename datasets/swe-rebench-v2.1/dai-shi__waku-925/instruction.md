waku dev error with generated fs router types
I have a project that doesn't have a home page / root index.tsx file. I hit an error trying to run the dev server on the latest `main` commit (901594c2195de5a7d601ca6ecda674202e9a0915):

```
Error: ENOENT: no such file or directory, open '/waku-project/src/pages/index.tsx'
    at Object.openSync (node:fs:562:18)
    at readFileSync (node:fs:446:35)
    at fileExportsGetConfig (file:///waku-project/node_modules/waku/dist/lib/plugins/vite-plugin-fs-router-typegen.js:68:30)
    at generateFile (file:///waku-project/node_modules/waku/dist/lib/plugins/vite-plugin-fs-router-typegen.js:76:42)
    at updateGeneratedFile (file:///waku-project/node_modules/waku/dist/lib/plugins/vite-plugin-fs-router-typegen.js:126:51) {
  errno: -2,
  code: 'ENOENT',
  syscall: 'open',
  path: '/waku-project/src/pages/index.tsx'
}
```

The `filePaths` given to `generateFile` in vite-plugin-fs-router-typegen.ts looks like this for my project:

```
[
  '/_layout.tsx',
  '/_layout.tsx',
  '/_layout.tsx',
  '/index.tsx',
  '/demo.tsx',
  '/index.tsx',
  '/detail.tsx',
  '/index.tsx',
  '/index.tsx',
  '/app.tsx'
]
```

I don't think that's right to not include the entry paths and only list the filenames.

~~Also, I think the `recursive` option for `fs/promises` readdir is newer than some of our targets (https://nodejs.org/api/fs.html#fspromisesreaddirpath-options).~~
