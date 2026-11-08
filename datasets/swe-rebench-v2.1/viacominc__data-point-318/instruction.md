Simplify DataPoint's API helpers/entity access
<!--
Thanks for your interest in the project. We appreciate bugs filed and PRs submitted!
Please make sure that you are familiar with and follow the Code of Conduct for
this project (found in the CODE_OF_CONDUCT.md file).

Please fill/un-comment out this template with all the relevant information so we can
understand what's going on and fix the issue.
-->

**Problem description**:

Requiring entities and helpers from DataPoint is currently a bit convoluted:

```js
const {Model, Request} = require('data-point').entities
const {constant, map} = require('data-point').helpers

// or

const DataPoint = require('data-point')
const {Model, Request} = DataPoint.entities
const {constant, map} = DataPoint.helpers

// or

const DataPoint = require('data-point')
DataPoint.entities.Model
DataPoint.entities.Request
DataPoint.helpers.constant
DataPoint.helpers.map

```

**Suggested solution**:

Simplify the access to these helpers/entities by changing the API to expose all entities and helpers from within the main module:

```js
const {
  Model,
  Request,
  constant,
  map
} = require('data-point')

// or

const DataPoint = require('data-point')

DataPoint.Model
DataPoint.Request
```

Essentially the change is from:

https://github.com/ViacomInc/data-point/blob/dac2133911173e3b9ab6ec4921a133a9b5c5f082/packages/data-point/lib/index.js#L8-L20

to this:

[HIDDEN]

### Additional contract requirements

- Keep the existing `entities` and `helpers` properties available alongside the new top-level exports.
