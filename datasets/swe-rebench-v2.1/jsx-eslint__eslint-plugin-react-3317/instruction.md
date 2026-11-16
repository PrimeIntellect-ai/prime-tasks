[`jsx-no-literals`]: no errors for children when `noAttributeStrings: true`
```js
'react/jsx-no-literals': [2, { noAttributeStrings: true }],
```

```js
import React from 'react';

export const WithAttributes = ({}) => <div title="foo bar" />;
export const WithChildren = ({}) => <div>baz bob</div>;
export const WithAttributesAndChildren = ({}) => (
  <div title="foo bar">baz bob</div>
);

```

Expected: the JSX inside of `WithChildren` produces an error (like it does when `noAttributeStrings: false`)

Actual: the JSX inside of `WithChildren` does not produce an error
