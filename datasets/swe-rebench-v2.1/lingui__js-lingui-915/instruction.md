t macro with variable id extracted as message with undefined id
**Describe the bug**
`t({id: foo})` calls are being extracted with `undefined` message id
```po
#~ messages.po

#: src/path/file.tsx:##
msgid "undefined"
msgstr ""
```

**To Reproduce**

```
// src/path/file.tsx

import {t} from "@lingui/macro"

const foo = t`foo`

const Component = () => {
  const text = t({id: foo})

  return <span>{text}</span>
}
```

**Expected behavior**
No `messages.po` changes

**Additional context**
Dependencies

```json
    "@lingui/cli": "3.2.3",
    "@lingui/loader": "3.2.3",
    "@lingui/macro": "3.2.3",
    "@lingui/react": "3.2.3",
    "babel-plugin-macros": "2.8.0",
    "react-scripts": "3.4.3",
    "typescript": "3.9.7",
```
