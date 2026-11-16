Test borken, but console show all conditions true
The test is breaking, but all conditions than the console show are true. I'm using chai plugin.
It's my rules json:

```json
{
  "rules": {
    "list": {
      "$listId": {
        ".write": "(newData.parent().parent().child('otherList1').child($listId).val() == true)
        	     && (newData.parent().parent().child('otherList2').child($listId).val() == false)"
      }
    }
  }
}
```

And it's is test file:

```js
const chai = require('chai');
const targaryen = require('targaryen/plugins/chai');
const { expect } = chai;
const { users } = targaryen;

chai.use(targaryen);

describe('list', function() {

  before(function() {
    targaryen.setFirebaseData({});
    targaryen.setFirebaseRules(require('../../database.rules.json'));
  });

  it('', () => {

    const updates = {
      'list/_listId1/id': '_listId1',
      'otherList1/_listId1': true,
      'otherList2/_listId1': false
    };

    expect({ uid: '_uid1' }).can.patch(updates).to.path('/');

  });

});

```
The console:

![captura de tela de 2016-12-21 16 18 35](https://cloud.githubusercontent.com/assets/13024620/21406462/8eaf37b2-c7aa-11e6-8dc5-837531ee14cb.png)

### Additional contract requirements

The result of a patch operation (`db.update(path, patch)`, also available as `database.update`) exposes an `info` property: a human-readable string summary of the permission-checking outcome.

`info` lists a per-path log entry for each path evaluated against rules.

When a path has no rules, `info` includes `/<path>: <no rules>` (for example `/bar: <no rules>`).

When a patch is denied, `info` includes `No .write rule allowed the operation.`.

For a denied patch operation, `info` includes the exact phrase `patch was denied.`.


- With debug enabled, when a patch evaluates a `.write` rule of `true` at `/foo`, `info` includes the exact text `/foo: write "true"`.
