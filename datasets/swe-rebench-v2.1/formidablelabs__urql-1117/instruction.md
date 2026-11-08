(retry) - Allow retryIf to avoid retrying subscriptions on non-network error
<!--
  Please describe your bug clearly and concisely.
  Include a screenshot or a reproduction to illustrate
  the bug and how to reproduce it.
  Please also leave a note on what version of urql you're using
  and include a list of exchanges (if any).
-->

i use both retry-exchange and subscriptions. if there is an error on the server, while generating a subscription-event, then the error correctly arrives to the client, retry-middleware does a retry, and from this point on, `useSubscription` will be triggered multiple times for the same event.

urql version & exchanges:
urql=1.10.2 or 1.10.3
retry-exchange=0.1.10

**Steps to reproduce**

i created a codesandbox-example, this is the server:
https://codesandbox.io/s/urql-sub-retry-problem-server-6rrhd (nothing special here)
this is the client:
https://codesandbox.io/s/urql-sub-retry-problem-client-h8ie7

open the client, open the url with the running example, and open devtools, watch the console-output. (do not leave this running too long, or the tab might become unresponsive)
the server is set up so that it generates a new event every second, and has a 60% chance to `throw` while doing so.
while you get no errors, the new events arrive correctly, but after the first error happens, retry happens, and things get to arrive duplicated. when more errors happen, it becomes even more duplicated.

if you change the codesandbox example, to switch `urql` to version `1.10.1`, then it is suddenly fixed. it now works correctly.

unfortunately, in my local codebase reverting to `urql=1.10.1` does not fix the problem. i do not understand why, maybe a combination of package-versions?

**Expected behavior**
actually i am not even sure what exactly should happen, a subscription-event cannot really be retried. but duplicate events should not happen.

**Actual behavior**
i am getting duplicate events.

<!--
  Your issue will be addressed much faster if you include a
  reproduction. Here are some templates to help you create one:
  - client: https://codesandbox.io/s/urql-issue-template-client-iui0o
  - server: https://codesandbox.io/s/urql-issue-template-server-0ufyz
-->

### Additional contract requirements

- When `retryIf` is provided, it receives the error and the failed operation as its second argument, so callers can distinguish operation kinds such as subscriptions.
- If `retryIf` returns `false` for an error, that operation is not retried and the error result is delivered.
