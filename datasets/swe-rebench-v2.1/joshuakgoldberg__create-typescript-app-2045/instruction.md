🐛 Bug: Transition mode crashes on major-version-only semver identifier
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Running `npx create-typescript-app` on a repo whose `package.json` contains partial semver identifiers should work:

```js
{
	"dependencies": {
		"debug": ">=4"
	},
}
```

### Actual

Running on https://github.com/JoshuaKGoldberg/debug-for-file/tree/017f4f35803c2fb970acf6236b110ed051fde005:

```plaintext
joshgoldberg ~/repos/debug-for-file $ npx create-typescript-app --add-cta-transitions
┌  ✨ create-typescript-app@2.15.6 ✨
│
●  Learn more on:
│    https://github.com/JoshuaKGoldberg/create-typescript-app
│
◇  Running with mode --transition using the config file:
│    create-typescript-app
│
│
◇  Detected --preset everything from existing files on disk.
│
◇  Inferred options from existing repository
│
■  Error running create-typescript-app:
│
■  TypeError: Invalid Version: 4
│      at new SemVer (/Users/josh/repos/debug-for-file/node_modules/.pnpm/semver@7.7.1/node_modules/semver/classes/semver.js:38:13)
│      at compare (/Users/josh/repos/debug-for-file/node_modules/.pnpm/semver@7.7.1/node_modules/semver/functions/compare.js:3:3)
│      at Object.gt (/Users/josh/repos/debug-for-file/node_modules/.pnpm/semver@7.7.1/node_modules/semver/functions/gt.js:2:29)
│      at useLargerVersion (file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/create-typescript-app@2.15.6_bingo-systems@0.5.4/node_modules/create-typescript-app/lib/blocks/blockPackageJson.js:113:19)
│      at file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/create-typescript-app@2.15.6_bingo-systems@0.5.4/node_modules/create-typescript-app/lib/blocks/blockPackageJson.js:126:7
│      at Array.map (<anonymous>)
│      at useLargerVersions (file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/create-typescript-app@2.15.6_bingo-systems@0.5.4/node_modules/create-typescript-app/lib/blocks/blockPackageJson.js:124:34)
│      at Object.produce (file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/create-typescript-app@2.15.6_bingo-systems@0.5.4/node_modules/create-typescript-app/lib/blocks/blockPackageJson.js:22:26)
│      at block.produce (file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/bingo-stratum@0.5.7_bingo-fs@0.5.4_bingo-systems@0.5.4_bingo@0.5.10_zod@3.24.2/node_modules/bingo-stratum/lib/creators/createBlock.js:15:32)
│      at produceBlock (file:///Users/josh/repos/debug-for-file/node_modules/.pnpm/bingo-stratum@0.5.7_bingo-fs@0.5.4_bingo-systems@0.5.4_bingo@0.5.10_zod@3.24.2/node_modules/bingo-stratum/lib/producers/produceBlock.js:9:26)
│
└  Leaving changes to the local directory on disk. 👋
```

### Additional Info

This comes from `useLargerVersion`. `existing` and `replacement` are both `>=4`.

🎁

### Additional contract requirements

- When the existing dependency version is `next` and the addon provides version `1.0.0`, the resulting dependency version must be `1.0.0`.
