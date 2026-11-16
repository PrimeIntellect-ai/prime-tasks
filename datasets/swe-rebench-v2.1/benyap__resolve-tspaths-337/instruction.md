Word "import" in comments confuses resolve-tspaths
This is similar to #311.

## Steps to Reproduce
To reproduce, build [this commit](https://github.com/gristlabs/grist-electron/commit/667392804eeb755984a34e902106bfdcac4e8a4e) of gristlabs/grist-electron. Make sure to use Node.js version 18.

```
git clone https://github.com/gristlabs/grist-electron
cd grist-electron
git checkout 6673928
git submodule init
git submodule update
yarn install
yarn run setup
yarn build
yarn run electron:preview
```

The last command should give the following error:
```
Error: Cannot find module 'app/common/gutil'
```

This is because resolve-tspaths failed to expand the import properly.

## More Info
To take a closer look, go to `core/_build/ext/app/electron/main.js`. This file is compiled from `ext/app/electron/main.ts`. On line 38, there is a word "import" in the comments. All imports after that line will not be correctly expanded by resolve-tspaths. The problem goes away if the word "import" is removed.

The minimal commands to see the problem are `tsc --build tsconfig-ext.json`, then `resolve-tspaths` in the `core` directory. You need to make `core/ext` point to `ext` in the grist-electron root before doing this.
