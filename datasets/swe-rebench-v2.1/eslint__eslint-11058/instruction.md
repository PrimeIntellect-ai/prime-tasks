`no-unreachable` reports EmptyStatements
Thank you for a wonderful tool.  Most times I think I find a bug, instead I learn a JS horror detail.

Can't figure this one out yet.  Don't think it's env related.

* ESLint - 4.3.0
* Node - 8.1.3
* NPM - 5.3.0
* Parser - babel-eslint
* Exhibits on Mac, Win10, Travis CI's debian

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js
John-Haugeland:jssm johnhaugeland$ cat .eslintrc
{

  "parser"  : "babel-eslint",
  "plugins" : [ ],
  "env"     : { "es6": true, "commonjs": true },

  "extends" : "eslint-config-stonecypher"

}
```

`eslint-config-stonecypher` in turn configures every current eslint rule, plus `eslint-plugin-` ... `flowtype`, `fp`, `jsdoc`, `ava`, `unicorn`, `new-with-error`, and `promise`

</details>

**What did you do? Please include the actual source code causing the issue.**

The following code triggers "no-unreachable" at the end of the switch, even though it's the last action in a default, ostensibly because of the `throw`.

<!-- Paste the source code below: -->
```js
const arrow_direction = arrow => {

  switch (arrow) {

    case '->': case '=>': case '~>':
      return 'right';

    case '<-': case '<=': case '<~':
      return 'left';

    case '<->': case '<-=>': case '<-~>':
    case '<=>': case '<=->': case '<=~>':
    case '<~>': case '<~->': case '<~=>':
      return 'both';

    default:
      throw new Error(`arrow_direction: unknown arrow type ${arrow}`);

  };

}
```

**What did you expect to happen?**
Nothing.  No code follows the `throw`.

This similar code does not trigger the warning, I expect because the throw is now outside the switch.

```javascript
const arrow_direction = arrow => {

  switch (arrow) {

    case '->': case '=>': case '~>':
      return 'right';

    case '<-': case '<=': case '<~':
      return 'left';

    case '<->': case '<-=>': case '<-~>':
    case '<=>': case '<=->': case '<=~>':
    case '<~>': case '<~->': case '<~=>':
      return 'both';

  };

  throw new Error(`arrow_direction: unknown arrow type ${arrow}`);

}
```

**What actually happened? Please include the actual, raw output from ESLint.**
```
/Users/johnhaugeland/projects/jssm/src/js/jssm.js
   22:7    warning  'arrow_direction' is assigned a value but never used  no-unused-vars
   22:7    warning  Missing "arrow_direction" variable type annotation    flowtype/require-variable-type
   22:25   warning  Missing return type annotation                        flowtype/require-return-type
   22:25   warning  Missing "arrow" parameter type annotation             flowtype/require-parameter-type
   44:4    warning  Unnecessary semicolon                                 no-extra-semi
   44:4    error    Unreachable code                                      no-unreachable
...
```

It's not like it's a big deal, or anything.  I moved the throws outside of the switch afterwards anyway, because in retrospect it's sorta gross.

It's just surprising, and I wonder whether it's legitimately a subtle bug.

Please have a nice day.
