t.update: cannot $merge and $remove at once
`update` returns immediately after processing the first top level command, so something like this is not possible: `const result = update(obj, { $merge: {a: [1, 2, 3] }, $remove: ['b'] })`

(Obviously I could use `const result = update(obj, { a: {$set: [1, 2, 3] }, $remove: ['b'] })`, but I'm trying to boil down to a simple example, we could want to merge multiple keys).

Here is a rough spec that shows this behavior, together with a 'fixed' version of `update` (`update2`) that passes. I'm not keen about the assumption that `value` has changed though, but comparing before and after values doesn't work as `$remove` (and several other commands), modifies the value object passed in.

```
import t from 'tcomb'

var isObject = require('tcomb/lib/isObject');
var getShallowCopy = require('tcomb/lib/getShallowCopy');

function update2(instance, spec) {
  if (process.env.NODE_ENV !== 'production') {
    assert(isObject(spec), function () { return 'Invalid argument spec ' + assert.stringify(spec) + ' supplied to function update(instance, spec): expected an object containing commands'; });
  }

  [HIDDEN]
        [HIDDEN]
      [HIDDEN]
}

describe('update', () => {
  const obj = {a: [1, 2], b: true}

  const methods = {tcomb: t.update, update2: update2}

  Object.keys(methods).forEach( (key) => {
    describe(`using ${key}`, () => {
      const update = methods[key]

      it('can $push', () => {
        const result = update(obj, { a: { $push: [3] } })
        expect(result).to.have.property('a').that.is.an('array').that.is.length(3)
        expect(result).to.have.property('b').that.equal(true)
      })

      it('can $remove', () => {
        const result = update(obj, { $remove: ['b'] })
        expect(result).to.have.property('a').that.is.an('array').that.is.length(2)
        expect(result).to.not.have.property('b')
      })

      it('can $push and $remove at once', () => {
        const result = update(obj, { a: { $push: [3] }, $remove: ['b'] })
        expect(result).to.have.property('a').that.is.an('array').that.is.length(3)
        expect(result).to.not.have.property('b')
      })

      it('can $merge and $remove at once', () => {
        const result = update(obj, { $merge: {a: [1, 2, 3] }, $remove: ['b'] })
        expect(result).to.have.property('a').that.is.an('array').that.is.length(3)
        expect(result).to.not.have.property('b')
      })

      it('can $set and $remove at once', () => {
        const result = update(obj, { a: {$set: [1, 2, 3] }, $remove: ['b'] })
        expect(result).to.have.property('a').that.is.an('array').that.is.length(3)
        expect(result).to.not.have.property('b')
      })
    })
  })
})
```

### Additional contract requirements

- A spec with multiple top-level commands must apply their effects to the returned value; for example, `$merge` and `$remove` can be used together. Applying a combined spec must not mutate the original instance.
