Rules do not work with named exports
Hello, and thanks for the plugin.

I tried to use these rules on my plugin today, but none of them seem to work, meaning that none of the rules were triggered.
I think this is because this plugin only looks for code matching `export default foo` or `module.exports = foo`.

My plugin does not use these and instead uses named exports. My plugin is a modern ESLint plugin written in TypeScript, and [using default exports in TypeScript is considered an anti-pattern](https://basarat.gitbook.io/typescript/main-1/defaultisbad).

For example, here is what [one of my rules](https://github.com/IsaacScript/isaacscript/blob/main/packages/eslint-plugin-isaacscript/src/rules/no-explicit-array-loops.ts) looks like:

```ts
import { ESLintUtils } from "@typescript-eslint/utils";

const createRule = ESLintUtils.RuleCreator(
  (ruleName) =>
    `https://github.com/IsaacScript/isaacscript/blob/main/packages/eslint-plugin-isaacscript/docs/rules/${ruleName}.md`,
);

export type Options = [];
export type MessageIds = "noExplicitArray";

export const noExplicitArrayLoops = createRule<Options, MessageIds>({
  name: "no-explicit-array-loops",
  meta: {
    type: "problem",
    docs: {
      description: "Disallows explicit iteration for arrays",
      recommended: "recommended",
      requiresTypeChecking: true,
    },
    schema: [],
    messages: {
      noExplicitArray:
        'Explicit iteration over arrays is disallowed. (Get rid of the "Object.values()".)',
    },
    fixable: "code",
  },
  defaultOptions: [],
  create(context) {
    // Rule logic here.
  },
});
```

Thus, I propose that the "detect rule" logic of this plugin is updated in some way. If you can advise on what the correct solution is, I can submit a pull request, as I would love to use the rules that this project offers. Thank you.

### Additional contract requirements

- A named ESM function declaration with one context parameter that returns an object is a rule.
- Rule detection must return `null` for these CommonJS named-property exports: `module.exports.rule = { create: function() {} };`, `exports.rule = { create: function() {} };`, `const rule = { create: function() {} }; module.exports.rule = rule;`, and `const rule = { create: function() {} }; exports.rule = rule;`.
