loginWithPopup is blocked by firefox since version 1.6.5
### Describe the problem
Using loginWithPopup in firefox in an onclick works in 1.6.4. However, in 1.6.5 the same code now triggers firefox pop blocker.

I have done some preliminary investigation and I believe the issue was introduced in [this commit](https://github.com/auth0/auth0-spa-js/pull/368/commits/6665dc071e7e27d480ef2b7d91673741fe571d5e).

[HIDDEN] In Girefox if you try to open a window asynchronously it will [no longer be treated as a user action ](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/User_actions).

### What was the expected behavior?

The window should open without being blocked by the popup blocker.

### Reproduction


**Can the behavior be reproduced using the [SPA SDK Playground](https://github.com/auth0/auth0-spa-js/blob/master/DEVELOPMENT.md#the-sdk-playground)?**

If so, provide steps:

Run the playground, click login with popup in firefox. Get a banner showing "firefox prevented this site from opening a pop up window". Console shows "Uncaught (in promise) Error: Could not open popup"

### Environment

> Please provide the following:

- **Version of `auth0-spa-js` used:**
- Listed above - any version after 1.6.4 has this issue
-
- **Which browsers have you tested in?**
- Issue occurs in firefox
-
- **Which framework are you using, if applicable (Angular, React, etc):**
- Vue
-
- **Other modules/plugins/libraries that might be involved:**
None
Cannot login if cookies are blocked using refresh tokens and local cache storage
Using the latest version 1.14.0. When I run loginwithpop up using social login (google), refresh tokens and cache set to localstorage. The login fails ,on second attempt I get this error in Safari:

[Error] TypeError: null is not an object (evaluating 't.organization')

	_callee$ (app.js:16429)
	l (chunk-vendors.js:27481:5863)
	(anonymous function) (chunk-vendors.js:27481:5648)
	asyncGeneratorStep (chunk-vendors.js:131)
	_throw (chunk-vendors.js:157)
	promiseReactionJob

In Firefox, if I set it to block all third party cookies it shows as:

TypeError: t is null
    node_modules auth0/auth0-spa-js/dist/auth0-spa-js.production.esm.js/</Vo</t.prototype.loginWithPopup/</<@http://localhost:8080/js/chunk-vendors.js:32
    s http://localhost:8080/js/chunk-vendors.js:32
    s http://localhost:8080/js/chunk-vendors.js:32
    c http://localhost:8080/js/chunk-vendors.js:32
    promise callback*a http://localhost:8080/js/chunk-vendors.js:32
    c http://localhost:8080/js/chunk-vendors.js:32
    promise callback*a http://localhost:8080/js/chunk-vendors.js:32
    c http://localhost:8080/js/chunk-vendors.js:32
    promise callback*a http://localhost:8080/js/chunk-vendors.js:32
    r http://localhost:8080/js/chunk-vendors.js:32
    r http://localhost:8080/js/chunk-vendors.js:32
    node_modules auth0/auth0-spa-js/dist/auth0-spa-js.production.esm.js/</Vo</t.prototype.loginWithPopup@http://localhost:8080/js/chunk-vendors.js:32
    _callee$ http://localhost:8080/js/app.js:17333
    l http://localhost:8080/js/chunk-vendors.js:36663
    _invoke http://localhost:8080/js/chunk-vendors.js:36663
    t http://localhost:8080/js/chunk-vendors.js:36663
    asyncGeneratorStep http://localhost:8080/js/chunk-vendors.js:131
    _next http://localhost:8080/js/chunk-vendors.js:153
    _asyncToGenerator http://localhost:8080/js/chunk-vendors.js:160
    _asyncToGenerator http://localhost:8080/js/chunk-vendors.js:149
    loginWithPopup http://localhost:8080/js/app.js:17364
    _callee$ http://localhost:8080/js/app.js:1220
    l http://localhost:8080/js/chunk-vendors.js:36663
    _invoke http://localhost:8080/js/chunk-vendors.js:36663
    t http://localhost:8080/js/chunk-vendors.js:36663
    asyncGeneratorStep http://localhost:8080/js/chunk-vendors.js:131
    _next http://localhost:8080/js/chunk-vendors.js:153
    _asyncToGenerator http://localhost:8080/js/chunk-vendors.js:160
    _asyncToGenerator http://localhost:8080/js/chunk-vendors.js:149
    loginClick http://localhost:8080/js/app.js:1231
    click http://localhost:8080/js/app.js:7562
    invokeWithErrorHandling http://localhost:8080/js/chunk-vendors.js:38806
    invoker http://localhost:8080/js/chunk-vendors.js:39131
    invokeWithErrorHandling http://localhost:8080/js/chunk-vendors.js:38806
    $emit http://localhost:8080/js/chunk-vendors.js:40835
    click http://localhost:8080/js/chunk-vendors.js:47527
    invokeWithErrorHandling http://localhost:8080/js/chunk-vendors.js:38806
    invoker http://localhost:8080/js/chunk-vendors.js:39131
    _wrapper http://localhost:8080/js/chunk-vendors.js:43860

How can I troubleshoot this? Am I doing something wrong?

My main goal is to allow logins using safari. All the posts on this issue says to use refresh tokens  and set cache to localstorage, however that doesn't seem to be working with Google OAuth login.

### Additional contract requirements

- When `loginWithPopup` is called from a click handler, the login popup window must be opened during that call, before the call hands control back to the caller, so that browsers such as Firefox do not block it.
- The login popup must be navigated to the Auth0 authorization page for the requested login, and the login completes once that popup sends the authorization response back to the application.
