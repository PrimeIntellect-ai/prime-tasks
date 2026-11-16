Rules that are fixable should say so in their documentation
Right now, we only say which rules are fixable in the overall README, but not in individual rule docs.

For example, eslint says in one of its [rule docs](https://eslint.org/docs/rules/eol-last):
> :wrench: The `--fix` option on the [command line](https://eslint.org/docs/user-guide/command-line-interface#fixing-problems) can automatically fix some of the problems reported by this rule.

We should update rule docs with this same notice and also add a test in `rule-setup.js` that fixable rules say this in their doc.
