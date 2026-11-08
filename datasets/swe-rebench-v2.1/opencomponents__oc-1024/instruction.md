context.setHeader from server.js not being applied when calling getData function oc-react-template
## This is effecting anyone one that is using a client getData call from oc-react-template and the server does a context.setHeader the header is not being set.

What I found is that headers are being set in component.js (below), but when a getData call is being make [HIDDEN]

Setting headers:
https://github.com/opencomponents/oc/blob/master/src/registry/routes/component.js#L29

Not setting headers:
https://github.com/opencomponents/oc/blob/master/src/registry/routes/components.js#L64

I have fixed this locally by adding this code below:
```
[HIDDEN]
```
In the result calling the function above:
```
[HIDDEN]
```

### Additional contract requirements

- When a client `getData` request resolves to a single component result, the headers returned by that component must be applied to the HTTP response.
- When a `getData` request resolves to more than one component result, the response headers are unspecified: an implementation may apply the headers of one of the results, or none of them.
