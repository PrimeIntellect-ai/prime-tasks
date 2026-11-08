protoconf: support field presence for prop `unique`
## Problem

This problem is caused by PR #96.

Given a **vertical map** embedding an **incell list**, but want **incell list** to be configured in vertical layout :

| ID | Property|
|--|--|
| map<uint32, Item> | []int32 |
| Item's ID | Item's properties |
| 1 | 101 |
| 1 | 102 |
| 1 | 103 |
| 2 | 201 |
| 2 | 202 |

When generating config, it will raise `error[E2005]: Map contains multiple empty keys.`

## Solution

https://github.com/tableauio/tableau/blob/49ea8d784e05076e34377ae35a330c09e4262fba/proto/tableau/protobuf/tableau.proto#L165-L166

Add field presence for prop `unique`:
```
[HIDDEN]
```


refer:
- https://github.com/protocolbuffers/protobuf/blob/main/docs/field_presence.md#go-example

### Additional contract requirements

The `unique` property must distinguish an omitted value from an explicitly supplied `false`; presence must not be inferred from the boolean value. In the vertical map with an incell list described above, setting `unique` explicitly to false must allow repeated rows for the same map key to be accumulated into that key's list rather than failing with E2005.
