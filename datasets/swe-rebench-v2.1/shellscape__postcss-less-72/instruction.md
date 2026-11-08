Incorrect value `rule.raws.semicolon`
<!--
  Please note: This template is not optional. Please fill in all fields and
  questions otherwise the issue may be closed. Please provide actual technical
  information about errors, if an error has occurred.
-->

* Node Version: `7.10.0`
* NPM Version: `4.2.0`
* postcss-less Version: `0.16.1`

If you have a large amount of code to share which demonstrates the problem you're experiencing, please provide a link to your
repository rather than pasting code. Otherwise, please paste relevant short snippets below.

### LESS

```less
a { .mixin; .mixin2; }
```

### JavaScript

```js
import postCssLess from 'postcss-less';
const less = `a { .mixin; .mixin2; }`;
const root = postCssLess.parse(less);
```

### Expected Behavior

`root.nodes[0].raws.semicolon` should be `true`.
`root.nodes[0].raws.after` should be ` `.

### Actual Behavior

`root.nodes[0].raws.semicolon` is `false`.
`root.nodes[0].raws.after` is `;  `.

### How can we reproduce the behavior?

Use example in `javascript` section.

Issue was created based on https://github.com/stylelint/stylelint/pull/2547.
Information about https://github.com/stylelint/stylelint/pull/2547#issuecomment-299712329.
Information about expected behavior based on `postcss` docs http://api.postcss.org/Node.html#raws
