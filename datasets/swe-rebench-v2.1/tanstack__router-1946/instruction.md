No typescipt error thrown if context is missing
### Describe the bug

No typescipt error thrown if context is missing from createRouter args.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-pte2gy

### Steps to Reproduce the Bug or Issue

Create a root route with a context with required prop
Create a router without specifying the context object
No typescript error is thrown

### Expected behavior

Typescript error should be thrown. The app should fail to compile a prod build.

### Screenshots or Videos

_No response_

### Platform

- OS: any
- Browser: any
- Version: any


### Additional context

_No response_
Context type inference on createRouter is not working anymore
### Describe the bug

When creating a new router with createRouter and a context value, the returned router doesn't contain valid typing on the options.context properties. This was working in version 1.34.5 but doesn't work anymore in version 1.44.2 (I did not test versions in between).

### Your Example Website or App

https://stackblitz.com/edit/github-dysjpq?file=src%2Fmain.tsx

### Steps to Reproduce the Bug or Issue

```tsx
import ReactDOM from 'react-dom/client';
import { RouterProvider, createRouter } from '@tanstack/react-router';
import { routeTree } from './routeTree.gen';

// Set up a Router instance
const router = createRouter({
  routeTree,
  defaultPreload: 'intent',
  context: {
    value: 'test',
  },
});

// Type inference is not working there (Property 'value' does not exist on type 'AnyContext'.)
const value = router.options.context.value;
```

### Expected behavior

Type inference on `router.options.context.value` should be inferred correctly.

### Screenshots or Videos

_No response_

### Platform

- OS: Windows
- Browser: Chrome


### Additional context

_No response_
