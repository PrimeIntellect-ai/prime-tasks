Naming route folder as "app" breaks nested router
### What version of HonoX are you using?

0.1.27

### What steps can reproduce the bug?

1. Deploy hono create x-basic
2. Create nested routes with index files /app and /app/nested
3. Open /app/nested in browser

### What is the expected behavior?

Page for /app/nested/index.tsx to be rendered

### What do you see instead?

404 not found page

### Additional information

_No response_

### Additional contract requirements

- Opening `/app/nested` must return the rendered page (HTTP status `200`) rather than a 404. The rendered page is the one defined by `app/nested/index.tsx`, which renders an `<h1>` heading with the text `Nested`.
