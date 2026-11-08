Anonymous functions sometimes given conflicting names, breaking code.
#### Input Code

index.js:
```js
#!/usr/bin/node
'use strict';

const babel = require('babel-core');

console.log(babel.transform(`
	'use strict';
	(() => {
		const con = console;
		const obj = {
			a() {
				con.log('Hi.');
			}
		};
		obj.a.log = str => {
			con.log('OUCH, should never get here! Should be "' + str + '".');
		};
		obj.a();
	})();
`, {presets: ['minify', 'env']}).code);
```

package.json:
```
{
  "name": "babelbug",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "",
  "private": true,
  "dependencies": {
    "babel-core": "^6.26.3",
    "babel-preset-env": "^1.6.1",
    "babel-preset-minify": "^0.4.0"
  }
}
```

#### Actual Output
<!-- If an error is thrown, please provide the stack trace here -->

```js
'use strict';(function(){var a=console,b={a:function a(){a.log('Hi.')}};b.a.log=function(b){
a.log('OUCH, should never get here! Should be "'+b+'".')},b.a()})();
```
Prints 'OUCH, should never get here! Should be "Hi.".'.

#### Expected Output

```js
'use strict';(function(){var a=console,b={a:function(){a.log('Hi.')}};b.a.log=function(b){
a.log('OUCH, should never get here! Should be "'+b+'".')},b.a()})();
```

Prints 'Hi.'.

#### Details
Note the incorrect `function a()` instead of `function()`, leading to the `con` variable being clobbered.

Same thing if using babel-preset-es2015 with babel-preset-minify.

Can't make a direct link to reproduce online – not sure why. But following this link, clicking on 'Plugins', on 'Only official plugins', typing 'mangle' and selecting minify-mangle-names reproduces it:
https://babeljs.io/repl/#?babili=false&browsers=&build=&builtIns=false&code_lz=JAcgrgzgpgBBAuAnAlgY3iA3AKGACjwEoYBeAPhgG9dhUB7AOwRnodKoBs6BzALhgAepCgEMOURPDwDCAXxzBajZnQBGAK3bVFwEUSo1FrAHRdueEAAlkxkIQWLZNeTTXrjI0z3YJEwgzomZhYA8gCqAMKWADRwABZ0YBwAJjAMUABuEjDcUPAwcRJQAIQwAMoJSamqsABEIDAA1HBITTAgtbb2zg5uHkQKsoQD2EA&debug=false&forceAllTransforms=false&shippedProposals=false&circleciRepo=&evaluate=true&fileSize=false&lineWrap=false&presets=es2015&prettier=false&targets=&version=6.26.0&envVersion=

Not sure whether this is a minify bug or a babel bug. Can't reproduce if running 'env' on the output of 'minify' or when running 'minify' on the output of 'env', only if doing both in the same step.
