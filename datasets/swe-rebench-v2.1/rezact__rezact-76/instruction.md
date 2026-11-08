Router onBeforeLeave Hook
This will provide a way to cancel navigation if a user may lose progress on their work if they navigate away, such as filling out a form
```javascript
router.route.onBeforeLeave((to, from) => return false)
```

### Additional contract requirements

- The hook is registered by calling `onBeforeLeave(callback)` on the route object that the router provides to page components. That same route object is available from the router instance as `router.currentRoute`.
- The callback is invoked with two arguments: `to` (the destination route) and `from` (the route being left). Both are route objects that expose a `pathname` property.
- Returning `false` from the callback cancels the navigation, so the current route remains rendered.
