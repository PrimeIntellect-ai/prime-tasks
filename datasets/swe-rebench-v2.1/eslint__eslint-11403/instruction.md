sort-keys: Cannot set property 'prevName' of null at SpreadElement
<!--
    ESLint adheres to the [JS Foundation Code of Conduct](https://js.foundation/community/code-of-conduct).

    This template is for bug reports. If you are here for another reason, please see below:

    1. To propose a new rule: https://eslint.org/docs/developer-guide/contributing/new-rules
    2. To request a rule change: https://eslint.org/docs/developer-guide/contributing/rule-changes
    3. To request a change that is not a bug fix, rule change, or new rule: https://eslint.org/docs/developer-guide/contributing/changes
    4. If you have any questions, please stop by our chatroom: https://gitter.im/eslint/eslint

    Note that leaving sections blank will make it difficult for us to troubleshoot and we may have to close the issue.
-->

**Tell us about your environment**

* **ESLint Version:** 5.14.0
* **Node Version:** 10
* **npm Version:**

**What parser (default, Babel-ESLint, etc.) are you using?**

`babel-eslint`

**Please show your full configuration:**

<details>
<summary>Configuration</summary>

<!-- Paste your configuration below: -->
```js

```

</details>

**What did you do? Please include the actual source code causing the issue, as well as the command that you used to run ESLint.**

<!-- Paste the source code below: -->
```ts
import UntypedJed from 'jed';
import { TranslatorConfig } from './types';

interface Jed {
  translate(input: string): Jed;
  ifPlural(value: number, plural: string): Jed;
  fetch(...args: any[]): string;
}

const DEFAULT_LANGUAGE_PACK = {
  domain: 'superset',
  locale_data: {
    superset: {
      '': {
        domain: 'superset',
        lang: 'en',
        plural_forms: 'nplurals=1; plural=0',
      },
    },
  },
};

export default class Translator {
  i18n: Jed;

  constructor(config: TranslatorConfig = {}) {
    const { languagePack = DEFAULT_LANGUAGE_PACK } = config;
    this.i18n = new UntypedJed(languagePack) as Jed;
  }

  translate(input: string, ...args: any[]): string {
    return this.i18n.translate(input).fetch(...args);
  }

  translateWithNumber(singular: string, plural: string, num: number = 0, ...args: any[]): string {
    return this.i18n
      .translate(singular)
      .ifPlural(num, plural)
      .fetch(...args);
  }
}
```

<!-- Paste the command you used to run ESLint: -->
```bash
beemo eslint "./packages/superset-ui-translation/{src,test,storybook}/**/Translator.{js,jsx,ts,tsx}"
```

**What did you expect to happen?**

Lint completes successfully. It works fine with `eslint@5.13.0`

**What actually happened? Please include the actual, raw output from ESLint.**

```
TypeError: Cannot set property 'prevName' of null
    at SpreadElement (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/rules/sort-keys.js:133:32)
    at listeners.(anonymous function).forEach.listener (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/util/safe-emitter.js:45:58)
    at Array.forEach (<anonymous>)
    at Object.emit (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/util/safe-emitter.js:45:38)
    at NodeEventGenerator.applySelector (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/util/node-event-generator.js:251:26)
    at NodeEventGenerator.applySelectors (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/util/node-event-generator.js:280:22)
    at NodeEventGenerator.enterNode (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/util/node-event-generator.js:294:14)
    at CodePathAnalyzer.enterNode (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/code-path-analysis/code-path-analyzer.js:632:23)
    at nodeQueue.forEach.traversalInfo (/Users/krist_wongsuphasawat/workspace/superset-ui/node_modules/eslint/lib/linter.js:750:28)
    at Array.forEach (<anonymous>)
```

See more at Travis
https://travis-ci.com/apache-superset/superset-ui/builds/101145033

**Are you willing to submit a pull request to fix this bug?**

Just posted #11403
