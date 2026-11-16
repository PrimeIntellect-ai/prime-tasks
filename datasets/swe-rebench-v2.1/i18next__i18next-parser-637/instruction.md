Cannot read property 'text' of undefined in jsx-lexer
<!--
Before you submit an issue we recommend you visit [docs](https://www.i18next.com/) or [docs](https://react.i18next.com/) or [StackOverflow](https://stackoverflow.com/) or similar and ask any questions you have or mention any problems you've had getting started with i18next.

**Please read this entire template before posting any issue. If you ignore these instructions and post an issue here that does not follow the instructions, your issue might be closed, locked.**
-->

## 🐛 Bug Report

Same behavior as https://github.com/i18next/i18next-parser/issues/199 where the spread operator generates an error using i18next CLI on `v4.1.1`


## To Reproduce

```
import React from 'react';
import PropTypes from 'prop-types';
import { withTranslation, Trans } from 'react-i18next';

// Refer to https://react.i18next.com/latest/trans-component#alternative-usage-components-array
const Component = (props) => {
  return <Trans {...props}>{props.children}</Trans>;
};

Component.propTypes = {
  children: PropTypes.node.isRequired
};

export default withTranslation()(Component);
```

Once I remove the `{...props}`, then this error disappears.

## Expected behavior

There should be no error.

## Your Environment

- *runtime version*: i.e. node v12.21
- *i18next version*: i.e. 19.5.3
- *os*: Mac
- *any other relevant information*: the workaround is to remove the spread operator.

### Additional contract requirements

When a `<Trans>` element has a JSX spread attribute, extraction must not throw. An explicit string-literal `defaults` prop on that same element must still be extracted.
