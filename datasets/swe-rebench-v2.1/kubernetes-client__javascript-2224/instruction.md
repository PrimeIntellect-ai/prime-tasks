List/Watch fails without error if the list function failse
**Describe the bug**
When listFn returns an error, the ListWatch is broken and no ERROR event is sent

**Client Version**
All

**Server Version**
n/a

**To Reproduce**
Fail the initial list function in a list/watch call.

**Expected behavior**
An error should be emitted to the done handler

See #2217
