rxjs-no-unsafe-takeuntil
### 💥 Missing Converter

-   `tslint-to-eslint-config` version: 1.5.0
-   `typescript-eslint` version: 4.6.0

#### TSLint Rule Name
[rxjs-no-unsafe-takeuntil](https://cartant.github.io/rxjs-tslint-rules/#rxjs-no-unsafe-takeuntil)

#### Package Source
rxjs-tslint-rules

### Additional contract requirements

- Add a public function `convertNoUnsafeTakeUntil(tslintRule: { ruleArguments: unknown[] })` in module `src/converters/lintConfigs/rules/ruleConverters/eslint-plugin-rxjs/no-unsafe-takeuntil`. It converts the TSLint rule `rxjs-no-unsafe-takeuntil` to the ESLint rule name `rxjs/no-unsafe-takeuntil`, using the `eslint-plugin-rxjs` plugin. The conversion result contains a single rule; when `ruleArguments` is non-empty it is forwarded as the rule's `ruleArguments`, and when `ruleArguments` is empty the rule has no `ruleArguments`.
