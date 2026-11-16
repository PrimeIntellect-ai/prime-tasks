Support comments inside JSX macros by ignoring empty jsx expressions
**Describe the bug**
When using a `<Trans>` element with a nested element like `{/* This is a comment */}`, it complains of @lingui/macro: Property value of ObjectProperty expected node to be of a type ["Expression","PatternLike"] but instead got "JSXEmptyExpression" Learn more: https://www.npmjs.com/package/@lingui/macro

**To Reproduce**
Steps to reproduce the behavior, possibly with minimal code sample, e.g:

```
import { Trans } from "@lingui/macro"

export default function App() {
   return (<Trans>
    {/* TODO: Come up with a better translation than this */}
    This should be translated!
  </Trans>)
}
```

**Expected behavior**
The comment should be ignored completely, leaving just the "This should be translated!" text.

**Additional context**
Add any other context about the problem here.

- jsLingui version ``2.9.1``
- Babel version ``babel-core@7.0.0-bridge.0``
- Your Babel config (e.g. `.babelrc`) or framework you use (Create React App, Meteor, etc.): Create React App
