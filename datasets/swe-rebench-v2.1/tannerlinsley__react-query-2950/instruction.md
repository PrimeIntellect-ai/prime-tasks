leak in query garbage collection
**Describe the bug**

Queries that should be garbage collected because the `cacheTime` has elapsed are kept in memory forever if the query was fetching when the last observer was removed.

**To Reproduce**
https://codesandbox.io/s/youthful-neumann-rh8t6?file=/src/index.js

note:
- `cacheTime` is 2 seconds
- the query takes 5 seconds to fetch
- it's best to wait until the query has loaded once, then trigger a refetch via window focus and click the button which will unmount the query while the fetch is happening.

**Expected behavior**
queries to be garbage collected correctly

**Additional context**

[HIDDEN]

https://github.com/tannerlinsley/react-query/blob/c1ae82ba188fd5abda5e256cac070145e5941447/src/core/query.ts#L216-L220
