[BUG] delete only processes first --metadata entry
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current Behavior

assume:
`mcdev del ../.. -m a:key -m b:key2 -m c:key3`
this will only execute delete for a:key but not even error for b:key2 or c:key3

### Expected Behavior

it should delete all 3 elements

### Steps To Reproduce

1. Go to '...'
2. Click on '....'
3. Run '...'
4. See error...


### Version

7.0.3

### Environment

- OS:
- Node:
- npm:


### Participation

- [X] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- `Mcdev.deleteByKey(businessUnit, selectedTypes, keyArr?)` in `lib/index.js` deletes one or more metadata records from the given Business Unit and resolves to `true` when every delete succeeds and `false` when any delete fails.
- `selectedTypes` is either a single metadata type name (a string) or a `TypeKeyCombo` object that maps metadata type names to one or more keys.
- `keyArr` is an optional string or array of strings with the identifiers of the metadata to delete. When `selectedTypes` is a `TypeKeyCombo`, the keys are taken from that object and any supplied `keyArr` is ignored.
