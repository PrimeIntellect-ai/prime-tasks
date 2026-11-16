not working with local package.json
I created minimal webpack project:
```
mkdir -p test/lib
cd test
npm init -f
npm i webpack webpack-cli
touch lib/index.js
```
`package.json`:
```
{
    "name": "webpack-imports",
    "version": "1.0.0",
    "type": "module",
    "imports": {
        "#index": "./lib/index.js"
    },
    "devDependencies": {
        "webpack": "^5.36.0",
        "webpack-cli": "^4.6.0"
    }
}
```
`lib/main.js`
```
import "#index";
```

Then run:
```
npx webpack build --entry ./lib/main.js
```

Error:
```
assets by status 126 bytes [cached] 1 asset
./lib/main.js 17 bytes [built] [code generated]

WARNING in configuration
The 'mode' option has not been set, webpack will fallback to 'production' for this value.
Set 'mode' option to 'development' or 'production' to enable defaults for each environment.
You can also set it to 'none' to disable any default behavior. Learn more: https://webpack.js.org/configuration/mode/

ERROR in ./lib/main.js 1:0-16
Module not found: Error: Can't resolve '#index' in '/mnt/hgfs/projects/work/tmp/webpack-imports/lib'
resolve '#index' in '/mnt/hgfs/projects/work/tmp/webpack-imports/lib'
  using description file: /mnt/hgfs/projects/work/tmp/webpack-imports/package.json (relative path: ./lib)
    Field 'browser' doesn't contain a valid alias configuration

webpack 5.36.0 compiled with 1 error and 1 warning in 200 ms
```

_Originally posted by @zdm in https://github.com/webpack/webpack/discussions/13254#discussioncomment-669831_
