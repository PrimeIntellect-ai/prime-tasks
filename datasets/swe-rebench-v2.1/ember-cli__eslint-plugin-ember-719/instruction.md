no-invalid-debug-function-arguments is not checking import source
```js
import { deprecate } from './-utils';

import isHtmlSafe from './string/is-html-safe';

export default deprecate(isHtmlSafe, 'isHtmlSafe', 'string.isHtmlSafe');
```

I have my own deprecate function, but the rule is triggering on it.

### Additional contract requirements

- The rule module `lib/rules/no-invalid-debug-function-arguments.js` exports `DEBUG_FUNCTIONS`, an array containing the names of the Ember debug functions whose argument order is checked. It includes `assert`, `deprecate`, and `warn`.
- Treat debug functions imported from `@ember/debug` as Ember debug functions: report calls with reversed arguments, but do not report same-named functions imported from other sources. Continue checking Ember-qualified calls.
