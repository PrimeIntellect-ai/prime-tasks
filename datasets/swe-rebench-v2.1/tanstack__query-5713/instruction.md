OnlineManager's setOnline doesn't seem to work with subscriptions correctly
### Describe the bug

I've got a custom React hook for subscribing to changes in `onlineManager.isOnline`:

```typescript
import { useState, useEffect } from "react";
import { onlineManager } from "@tanstack/react-query";

export default function useIsOnline() {
  const [isOnline, setIsOnline] = useState(onlineManager.isOnline());

  useEffect(() => {
    const unsubscribe = onlineManager.subscribe(() => {
      console.log(`Online: ${onlineManager.isOnline()}`);
      setIsOnline(onlineManager.isOnline());
    });

    return () => unsubscribe();
  }, []);

  return isOnline;
}
```

It works great when default behavior is in place. But instead of relying on browser's `online`/`offline` events I've created a hook with `networkMode: 'always'` that periodically checks connection to API and depending on success/error of the request I manually set online state using `onlineManager.setOnline`.

The problem is `onlineManager.setOnline(false)` doesn't trigger callback in the subscription or maybe I am a bit misunderstanding the concept of `OnlineManager`.

### Your minimal, reproducible example

https://codesandbox.io/s/focused-williamson-gxks92

### Steps to reproduce

1. Set up subscription through `onlineManager.subscribe`.
2. Manually call `onlineManager.setOnline(false)`.

### Expected behavior

Expect the callback to be executed on both `onlineManager.setOnline(true)` and `onlineManager.setOnline(false)`.

### How often does this bug happen?

Every time

### Screenshots or Videos

_No response_

### Platform

- OS: Windows.
- Browser: Any modern one.

### Tanstack Query adapter

react-query

### TanStack Query version

4.28.0

### TypeScript version

4.9.4

### Additional context

_No response_
