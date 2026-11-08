slice() does not accept 0 as first parameter
**Describe the bug**
Slice returns the following error when trying to pass 0 as first parameter
`.slice(start, optional) args need to be inferior to the string length at line 6, column 12 at flow [Default]`

**To Reproduce**
Check this code https://play.csml.dev/bot/2874f635-3fa2-4154-a760-4d65dee6c3f7

**Expected behavior**
It should accept 0 as first parameter
