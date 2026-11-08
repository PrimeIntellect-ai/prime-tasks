v4: Using hydrate during an ongoing "initial" fetch overwrites the isFetching status
### Describe the bug

If you `hydrate` a previous state while an "initial" fetch is ongoing the `status`, `fetchStatus` and derived booleans no longer reflect the state of the query.

### Your minimal, reproducible example

https://codesandbox.io/s/zen-diffie-klzj6l?file=/src/App.js

### Steps to reproduce

### In the attached CodeSandbox
1. Refresh the Page
2. Click "Hydrate State" button within 5secs

### Expected behavior

As a user, I expected the `isFetching` status to always be `true` when the query `isFetching`

### How often does this bug happen?

Every time

### Screenshots or Videos

_No response_

### Platform

- OS: Windows 10
- Browser: Chrome 117.0.5938.132
- Project: React, TypeScript via Vite


### Tanstack Query adapter

react-query

### TanStack Query version

v4.35.3

### TypeScript version

v5.0.2

### Additional context

For context on how we stumbled across this... We wrote a custom `Persister` that stores the cache encrypted in IndexedDB. It uses a per-user `key` that is returned from the API. Because of this, some `useQuery` calls have to happen first before we can know the current `user` and their `key`. As such the `Persister` is inactive initially but when a `key` is set, it attempts to `hydrate` (using IndexedDB) and becomes a functional `Persister`.

This generally works well, as the hydrated state ([as per the docs](https://tanstack.com/query/latest/docs/react/reference/hydration#:~:text=If%20the%20queries%20included%20in%20dehydration%20already%20exist%20in%20the%20queryCache%2C%20hydrate%20does%20not%20overwrite%20them%20and%20they%20will%20be%20silently%20discarded.)) does not overwrite any queries that might have happened in the meantime. It does however remove any subtle loading indicators, for those queries that are still being refreshed in the background. Hence this bug report.
