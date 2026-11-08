(svelte) - assigning context only retriggers execution once
<!--
  Please describe your bug clearly and concisely.
  Include a screenshot or a reproduction to illustrate
  the bug and how to reproduce it.
  Please also leave a note on what version of urql you're using
  and include a list of exchanges (if any).
-->

urql version & exchanges:

Using `@urql/svelte` v1.2.2

**Steps to reproduce**

Attempt to use the following method to refresh/refetch/reexecute a query **more than once:** https://formidable.com/open-source/urql/docs/basics/svelte/#reexecuting-queries

**Expected behavior**

The query is re-executed each time `refresh` is called

**Actual behavior**

The query is only executed the first time, and subsequent calls to `refresh` fail to trigger a backend request

<!--
  Your issue will be addressed much faster if you include a
  reproduction. Here are some templates to help you create one:
  - client: https://codesandbox.io/s/urql-issue-template-client-iui0o
  - server: https://codesandbox.io/s/urql-issue-template-server-0ufyz
-->
