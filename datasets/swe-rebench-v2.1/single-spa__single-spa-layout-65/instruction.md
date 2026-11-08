LayoutEngine: route matching with only trailing "/"
**Describe the bug or question**
When defining base path of  "/something" and route path of "/", the route will only match to "/something/" and not "/something". Since route does not allow empty strings as a route.

**Expected behavior**
route "/something" will match

**Screenshots and/or console output**
If applicable, add screenshots or console output to help explain your problem.

**Additional context**
Why is empty route string not allowed when according to documentation leading and trailing slashes are not needed?
