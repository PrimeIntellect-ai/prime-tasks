Ignored File is written
I have a set of files ignored:
```
dist/
package.json
.babelrc
```

However, when saving the `.babelrc` file prettier is being run against it and the file is being modified.

![prettier-0 55 1-babel](https://user-images.githubusercontent.com/2998575/44487393-d0ab1180-a61b-11e8-82a6-96e6b6133000.gif)

Running `npx prettier .babelrc` does not have this issue (`npx prettier` is running version 1.14.2 if that matters)

Output of the `Prettier: Debug` command:
<details>

```
Atom version: 1.29.0
prettier-atom version: 0.55.1
prettier: bundled
prettier version: 1.13.4
prettier-eslint version: 8.8.2
prettier-atom configuration: {
  "formatOnSaveOptions": {
    "isDisabledIfNoConfigFile": true,
    "isDisabledIfNotInPackageJson": true,
    "showInStatusBar": true,
    "enabled": false,
    "respectEslintignore": true,
    "excludedGlobs": [],
    "whitelistedGlobs": []
  },
  "useEslint": false,
  "useStylelint": false,
  "prettierEslintOptions": {
    "prettierLast": false
  }
}
```

</details>
