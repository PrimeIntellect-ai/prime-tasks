Early issue with nested `useRoutes`
Sorry for the vague issue but I just thought I would give you a heads up while investigating.
Since upgrading to `1.0.0-rc.3` (Also tried `rc6`) we have been having issues with previously working nested `useRoutes`.

The basic structure of our app is as follow

An "App" with `useRoutes` that either maps to a list page or a view entity page
`basePath` is `foo/bar/entities`
Routes are similar to the following
```
const routes = {
    '/': () => <ListPage />,
    '/:id/*': ({ id }) => (
        <ViewPage id={id} />
    ),
}
```

A view entity page with `useRoutes` that maps to 3 tabs within the page,
`basePath` is `foo/bar/entities/<id>` where `id` is a numeric id.
Routes are similar to the following
```
const routes = {
    "/tab1": () => <Component1 />,
    "/tab2": () => <Component2 />,
    "/tab3": () => <Component3 />
}
```

Previously (0.5.8) we were using `usePath` within one of the tabs (so 2 `useRoutes` deep) with no problems, it would always return the path we expected (`/tab2`)
Now however, if you land on tab2 (i.e. start a new browser tab at the  url `foo/bar/entities/1/tab2`) `usePath` will return the correct value (`/tab2`)
But as soon as you navigate to a different tab `usePath` (called within the tab) starts returning  `/1/<tabNo>`. The `basepath` in the context is correct (has the `id` at the end of the path), but it's like it calculated the `path` based on the `basePath` of the router one level higher.

```
context = { path: '/1/tab2', basePath: 'foo/bar/entities/1' }
```

I'll keep adding detail to this issue as I investigate, but I thought it might be possible you have an idea what's going on.

Thanks

### Additional contract requirements

- `usePath(basePath?: string)` returns the current location path as a string.
- When `basePath` is provided, the returned path is relative to that `basePath`; the `basePath` prefix is not part of the returned value.
- When `basePath` is omitted, the nearest router's base path is used.
