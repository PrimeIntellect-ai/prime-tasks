Explicit target for online event
Hi, currently we subscribe and unsubscribe to `'online'` event using global `addEventListener` and `removeEventListener`

Unfortunately there seems to be a Chrome bug triggered by Sentry's SDK which leads to `TypeError`s when `this` is `undefined`. More info in [this issue](https://github.com/getsentry/sentry-javascript/issues/2074).
It seems like bug is pretty tricky to fix on Sentry's side, but it's pretty easy to fix on SWR's side. I've created a PR with a [fix](https://github.com/zeit/swr/pull/300)

Also we leak subscriptions, because the assignment to reconnect is wrong, but that seems to be addressed in [this PR](https://github.com/zeit/swr/pull/297)

### Additional contract requirements

- Subscribing to the `online` event must use `window` as the event target (`window.addEventListener('online', ...)`), and unsubscribing on unmount must use `window.removeEventListener('online', ...)`. Neither call may be made as an unbound global function.
- Dispatching an `online` event on `window` while a hook is mounted revalidates its data.
