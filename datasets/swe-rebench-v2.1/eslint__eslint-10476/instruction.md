Do not fail on unrecognized logical operators
ESLint throws an error when trying to use the [nullish coalescing operator](https://github.com/tc39/proposal-nullish-coalescing) (`foo ?? bar`):

```
Error: unreachable
      at CodePathState.popChoiceContext (node_modules/eslint/lib/code-path-analysis/code-path-state.js:444:23)
      at processCodePathToExit (node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:434:19)
      at CodePathAnalyzer.leaveNode (node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:627:9)
      at Traverser.leave (node_modules/eslint/lib/linter.js:959:32)
      at Traverser.__execute (node_modules/estraverse/estraverse.js:397:31)
      at Traverser.traverse (node_modules/estraverse/estraverse.js:491:28)
      at Traverser.traverse (node_modules/eslint/lib/util/traverser.js:31:22)
      at Linter._verifyWithoutProcessors (node_modules/eslint/lib/linter.js:953:19)
      at preprocess.map.textBlock (node_modules/eslint/lib/linter.js:994:35)
      at Array.map (<anonymous>)
      at Linter.verify (node_modules/eslint/lib/linter.js:993:42)
      ...
```

That operator is part of a proposal in Stage 1, so according to the ESLint policy it doesn't have official support, but it shouldn't fail when it's present in the AST (from a different parser).

This problem happens for any operator other than `&&` and `||` in a logical expression, which are explicitly handled in the code.

This is just to track the discussion we're having in #10399.

**Affected ESLint versions**: v4.19.1 (latest stable) and v5.0.0-rc.0 (latest).
