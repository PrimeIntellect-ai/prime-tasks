[bug] singleQuote option from API call does not work on latest release
<!--

BEFORE SUBMITTING AN ISSUE:

1.  Search for your issue on GitHub: https://github.com/prettier/plugin-php/issues
    A large number of opened issues are duplicates of existing issues.
    If someone has already opened an issue for what you are experiencing,
    you do not need to open a new issue — please add a 👍 reaction to the
    existing issue instead.

2.  We get a lot of requests for adding options, but Prettier is
    built on the principle of being opinionated about code formatting.
    This means we have a very high bar for adding new options.
    Find out more: https://prettier.io/docs/en/option-philosophy.html

Tip! Don't write this stuff manually.

1. Go to https://loilo.github.io/prettier-php-playground/
2. Paste your code and set options
3. Press the "Report issue" button in the lower right

-->

## Environment

- **Prettier 3.x**
- **PHP Plugin 0.22.1**

```js
 $  yarn list | grep prettier
├─ @prettier/plugin-php@0.22.1
...
├─ prettier@3.1.1

```


## Current behaviour

In recent release (at least `0.22.1`), `prettier.format` API call like below does not respect `singleQuote` option. Other options are respected as like before.

```js
 $  cat test.js
import prettier from "prettier/standalone";
import prettierPluginPhp from "@prettier/plugin-php/standalone";

console.log((await prettier.format(`<?php echo link_to_route("frontend.users.user.show", $users["name"], $users['_id']); ?>`, {
  plugins: [prettierPluginPhp],
  singleQuote: true,
  parser: "php",
})));

```

It will outputs like below. You can see double quote is still double quote.

```js
 $  node test.js
<?php echo link_to_route(
    "frontend.users.user.show",
    $users["name"],
    $users['_id']
); ?>

```

### Expected behaviour

Respect `singleQuote` option as like before.

0.19.7 is OK. I think this regression is introduced since v0.20.0

```js
 $  cat package.json
{
  "dependencies": {
    "@prettier/plugin-php": "0.19.7",
    "prettier": "^2.0.0"
  }
}

 $  cat test.mjs
import prettier from "prettier/standalone.js";
import prettierPluginPhp from "@prettier/plugin-php/standalone.js";

console.log((prettier.format(`<?php echo link_to_route("frontend.users.user.show", $users["name"], $users['_id']); ?>`, {
  plugins: [prettierPluginPhp],
  singleQuote: true,
  parser: "php",
})));

```


```js
 $  node test.mjs
<?php echo link_to_route(
    'frontend.users.user.show',
    $users['name'],
    $users['_id']
); ?>

```

[HIDDEN] I'll create the PR.
