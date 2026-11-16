No builtin mechanism for remounting on path param changes
### Which project does this relate to?

Router

### Describe the bug

This issue is a result from a discussion I had with @schiller-manuel in https://discord.com/channels/719702312431386674/1316448877670563931.

Currently local state is preserved when navigating between two instances of the same route with different path params, i.e. navigating from `/posts/1` to `/posts/2`. In our app we want to treat path param changes as completely new instances of the page with forced remounts, like if we were using `<PostPage key={params.postId} />` at the top level. There's currently no mechanism for opting into this behavior.

The way we mentally think about our routes is that path params take you to a new page, while search params configure the current page. So the mechanism has to allow for search params to change without remounting as well. We were surprised to find that navigating `/posts/1 => /posts/2` we ended up in a different state than when navigating `/posts/1 => / => /posts/2`.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-kgrqvrxv?file=src%2Froutes%2Fposts.%24postId.tsx

### Steps to Reproduce the Bug or Issue

asd

### Expected behavior

sad

### Screenshots or Videos

_No response_

### Platform

- OS: [e.g. macOS, Windows, Linux]
- Browser: [e.g. Chrome, Safari, Firefox]
- Version: [e.g. 91.1]asd


### Additional context

_No response_

### Additional contract requirements

- A route can opt into remounting its component when its own path parameters change while that route stays active. The per-route option is `remountDeps`. The router option `defaultRemountDeps` provides the same policy for every route that does not define its own `remountDeps`.
- Both options are functions that receive an object with the fields `routeId` (the id of the matched route), `search` (that route's validated search object), `params` (that route's path parameters) and `loaderDeps` (that route's loader dependencies). They return a JSON-serializable value.
- When such a function returns a value that differs from the value returned for the previous navigation to the same route, the route's component is remounted. When it returns the same value, the component stays mounted.
- A route that has neither `remountDeps` nor an applicable `defaultRemountDeps` keeps its component mounted when only its path parameters change.
- For a route whose policy returns only its params, changing only its search parameters does not remount its component.
