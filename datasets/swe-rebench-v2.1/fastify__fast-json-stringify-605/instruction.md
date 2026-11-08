Broken error message for missing required property
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the regression has not already been reported


### Last working version

v5.5.0

### Stopped working in version

v5.6.0

### Node.js version

18.x

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

ventura

### 💥 Regression Report

The error message is now reporting "NaN" instead of the property name for the latest fast-json-stringify release.

### Steps to Reproduce

Run the following in this repo:

```
'use strict'

const assert = require('assert')
const fjs = require('./index')
const schema = {
  type: 'object',
  properties: {
    fullName: { type: 'string' },
    phone: { type: 'number' }
  }
}

const input = {
  fullName: 'Jone',
  phone: 'phone'
}

const render = fjs(schema)

try {
  render(input)
} catch (err) {
  assert.equal(err.message, 'The value "phone" cannot be converted to a number.')
}
```

### Expected Behavior

The correct property name is listed in the error message
