removeAll method of entity is not working.
https://github.com/reduxjs/redux-toolkit/blob/c89d5e2c6d3a4c1cc14a96db94d823314c4624e4/src/entities/unsorted_state_adapter.ts#L67-L72

Hi, teams.
I tested removeAll method, but it didn't work.
It looks incorrect usage of Object.assign.

```javascript
function removeAll(state: R): any {
   [HIDDEN]
     ids: [],
     entities: {}
   })
 }
```

[HIDDEN]

can you check it?

### Additional contract requirements

- `removeAll` must clear the supplied state in place by emptying its `ids` array and `entities` map, and return the same state instance.
