AboutPageSideNavBar: Warning: Each child in a list should have a unique "key" prop.
## Description
This component is not including a unique key prop.

### Steps to reproduce

browse to localhost:8000/trademark

### Expected result
No errors or warnings in the dev console.

### Actual result
```
react_devtools_backend.js:2560 Warning: Each child in a list should have a unique "key" prop.


Check the render method of `AboutPageSideNavBar`. See https://fb.me/react-warning-keys for more information.
    in Fragment (created by AboutPageSideNavBar)
    in AboutPageSideNavBar (at trademark.tsx:21)
    in main (at trademark.tsx:20)
    in div (at Layout/index.tsx:37)
    in Layout (at trademark.tsx:19)
    in TrademarkPage (created by PageRenderer)
    in PageRenderer (at query-result-store.js:90)
    in PageQueryStore (at root.js:27)
    in RouteHandler (at root.js:49)
    in div (created by FocusHandlerImpl)
    in FocusHandlerImpl (created by Context.Consumer)
    in FocusHandler (created by RouterImpl)
    in RouterImpl (created by Context.Consumer)
    in Location (created by Context.Consumer)
    in Router (at root.js:44)
    in ScrollHandler (at root.js:40)
    in RouteUpdates (at root.js:39)
    in EnsureResources (at root.js:37)
    in LocationHandler (at root.js:95)
    in LocationProvider (created by Context.Consumer)
    in Location (at root.js:94)
    in Root (at root.js:102)
    in MDXProvider (at wrap-root-element.js:65)
    in MDXScopeProvider (at wrap-root-element.js:64)
    in _c
    in Unknown (at wrap-root-element.js:72)
    in StaticQueryStore (at root.js:112)
    in ErrorBoundary (at fast-refresh-overlay/index.js:116)
    in DevOverlay (at root.js:111)
    in RootWrappedWithOverlayAndProvider (at app.js:174)
```

### Additional contract requirements

- The rendered output must contain no whitespace-only text content between the containing `<div>` and `<nav class="side-nav-about">`.
