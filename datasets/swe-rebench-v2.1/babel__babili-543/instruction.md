Syntax errors after minifying unicode
Trying to use [mathiasbynens/he](https://github.com/mathiasbynens/he) to encode html entities in the browser, but after adding the library, the app has started getting syntax errors in Safari and Firefox.

The offending character seems to be a unicode character, that appears in the source after minification.

Here's the result of running the corresponding snippet of code in [Babel's REPL with Babili enabled](https://babeljs.io/repl/#?babili=true&evaluate=true&lineWrap=false&presets=es2015&targets=&browsers=&builtIns=false&code=let%20a%20%3D%20%7B%20'%5Cu2118'%3A'wp'%20%7D&experimental=false&loose=false&spec=false&playground=false):

```js
let a = { '\u2118':'wp' };
// becomes
'use strict';var a={℘:'wp'};
```

Visiting that link in Firefox 50.1.0 results in an "Illegal character error" in the REPL. Seeing as it works fine without Babili, I'm guessing this is a bug, rather than a deliberate constraint.

Pretty sure it happens in [babel-plugin-transform-property-literals](https://github.com/babel/babili/tree/master/packages/babel-plugin-transform-property-literals) as it turns the string into a literal key.

### Additional contract requirements

- The transform must also remove the quotes from the property keys `default` and `import`, emitting them as unquoted keys.
- The string property keys `ಠ_ಠ` and `Ǽ` must be emitted as unquoted keys, while `℘` and `𐊧` must remain quoted.
