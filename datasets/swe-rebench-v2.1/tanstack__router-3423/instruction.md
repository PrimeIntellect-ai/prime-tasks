Cannot update path params when navigating to `'.'`
### Which project does this relate to?

Router

### Describe the bug

I wrote a hook which should replace the slug in the URL if it doesn't match reality anymore.
For example `/projects/here-is-the-name-123` -> `/projects/new-name-123`.

```ts
navigate({ to: '.', params: { slug: 'new-name' }, replace: true });
```

Replacing `search` works without issues this way but not with `params`.

### Your Example Website or App

https://stackblitz.com/edit/github-aitiwm?file=src%2Fmain.tsx

### Steps to Reproduce the Bug or Issue

1. Click on "Project 123" or "Document 123" link
2. See old slug from path params rendered
3. It should replace after 1 second but it does not

You can try replacing the `to: '.'` by a real route and see how it works but this then does not work for 2 different routes anymore.

### Expected behavior

Path params to get replaced when navigating to `'.'`.

### Screenshots or Videos

_No response_

### Platform

- OS: macOS
- Browser: Edge
- Version: 129


### Additional context

_No response_
The relative routing does not allow updating the path params using the <Link> component.
### Which project does this relate to?

Router

### Describe the bug

I am attempting to update only the path params from the current route, but the params are not updating. This seems to work for `search` params.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-hjja2d?file=src%2Froutes%2Fposts.%24postId.tsx

### Steps to Reproduce the Bug or Issue

1. Go to the stackblitz.
2. Click on the posts link and select the first post.
3. There should be a link on that page that says "Switch to post 2"
4. Attempt to click on the link
5. Notice the path is not updated

### Expected behavior

Path params to get replaced when navigating to '.'.

### Screenshots or Videos

_No response_

### Platform

- OS: [e.g. macOS, Windows, Linux]
- Browser: [e.g. Chrome, Safari, Firefox]
- Version: [e.g. 91.1]


### Additional context

This might be related to #2415, but I wasn't sure since that is using `navigate` instead of a link.
