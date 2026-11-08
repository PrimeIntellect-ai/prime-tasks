Support route parameters
```js
import { constructRoutes } from 'single-spa-layout';

const routes = constructRoutes({
  routes: [
    { type: 'route', path: "/user/:id/settings", routes: [] },
  ]
})
```
