[Webpack 3?] Duplicate declaration error
I've been trying to isolate this error, but I think that it has something to do with Webpack 3 and I can't pull anything of value from Babili and Webpack.

However, you can reproduce this issue by:

```
git clone https://github.com/ckeditor/ckeditor5-build-classic.git
git co babili-webpack-error
npm i
npm run build-ckeditor
```

This is the output I get:

```
(babili-webpack-error b720deb) p@m /workspace/test/ckeditor5-build-classic> npm run build-ckeditor

> @ckeditor/ckeditor5-build-classic@0.2.0 build-ckeditor /workspace/test/ckeditor5-build-classic
> ./bin/build-ckeditor.sh

Building 'build/ckeditor.js'...

Hash: 50fb7c52c064ebfdf790
Version: webpack 3.0.0
Time: 3798ms
          Asset    Size  Chunks                    Chunk Names
    ckeditor.js  405 kB       0  [emitted]  [big]  main
ckeditor.js.map  484 kB       0  [emitted]         main
  [37] ./ckeditor.js 191 bytes {0} [built]
  [58] (webpack)/buildin/harmony-module.js 596 bytes {0} [built]
  [59] (webpack)/buildin/global.js 509 bytes {0} [built]
    + 88 hidden modules

ERROR in unknown: Duplicate declaration "count"

Done.
```

This is the Webpack config: https://github.com/ckeditor/ckeditor5-build-classic/blob/babili-webpack-error/webpack.config.js

And the crucial file is this one: https://github.com/ckeditor/ckeditor5-typing/blob/958eeb26c6d862de3cdfbf53efd0a554e3c8e13e/src/typing.js

It imports:

* https://github.com/ckeditor/ckeditor5-typing/blob/958eeb26c6d862de3cdfbf53efd0a554e3c8e13e/src/input.js
* https://github.com/ckeditor/ckeditor5-typing/blob/958eeb26c6d862de3cdfbf53efd0a554e3c8e13e/src/delete.js

Which both depends on:

* https://github.com/ckeditor/ckeditor5-typing/blob/958eeb26c6d862de3cdfbf53efd0a554e3c8e13e/src/changebuffer.js

Both of these modules import `count` function and I think that this is that duplicated `count` identifier.

If I disable Babili plugin in `webpack.config.js` everything works fine. I also checked that builds done without Babili run correctly so most likely the issue is not on Webpack's side.

Output without Babili:

```
(babili-webpack-error b720deb M3) p@m /workspace/test/ckeditor5-build-classic> npm run build-ckeditor

> @ckeditor/ckeditor5-build-classic@0.2.0 build-ckeditor /workspace/test/ckeditor5-build-classic
> ./bin/build-ckeditor.sh

Building 'build/ckeditor.js'...

Hash: 50fb7c52c064ebfdf790
Version: webpack 3.0.0
Time: 759ms
          Asset    Size  Chunks                    Chunk Names
    ckeditor.js  405 kB       0  [emitted]  [big]  main
ckeditor.js.map  484 kB       0  [emitted]         main
  [37] ./ckeditor.js 191 bytes {0} [built]
  [58] (webpack)/buildin/harmony-module.js 596 bytes {0} [built]
  [59] (webpack)/buildin/global.js 509 bytes {0} [built]
    + 88 hidden modules

Done.
```

I've checked the unminified output but I can't find anything there which would suspiscious.

I'm using webpack 3.0.0 and babili-webpack-plugin 0.1.2.
