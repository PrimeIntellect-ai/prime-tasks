Class on active links
If the `Link` component has the path `/login` and the user is currently navigated to `/login`, the Link component could have a class labelling it as an active link as used in the vue-router: https://router.vuejs.org/api/#linkactiveclass

The API could follow after react-router: https://reacttraining.com/react-router/web/api/NavLink

Additionally, a class for exact and non-exact matching would be appreciated. For example, if the user is at `/user/login` the `/user` Link could have an `link-active` class while the `/user/login` Link could have an `link-active-exact` class.

### Additional contract requirements

Provide an opt-in `ActiveLink` component that accepts `href`, `activeClass`, and `exactActiveClass` props. When the current path starts with `href`, it applies `activeClass`; when the current path equals `href`, it also applies `exactActiveClass`. The classes are added to any supplied `className`. This makes the active styling opt-in rather than changing ordinary links.
