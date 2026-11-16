(graphcache) - Partial results aren't refetched
<!--
  Please describe your bug clearly and concisely.
  Include a screenshot or a reproduction to illustrate
  the bug and how to reproduce it.
  Please also leave a note on what version of urql you're using
  and include a list of exchanges (if any).
-->

Partial results on arrays are not being refetched when required data is missing.

urql version & exchanges:
"urql": "^2.0.4"
 "@urql/exchange-graphcache": "^4.1.4"
Schema integrated.

**Steps to reproduce**

1st query:
```
project {
  id
}
```
returns `[ { id: 1} ]`

2nd query:
```
project {
  id
  title
}
```
Queries are executed sequentially.

**1st Working scenario (when missing optional field)**

If `title` field is `optional` in schema, then 2nd query returns partial results `[ { id: 1, title: null } ]`, results are marked as `stale` and fallbacks to refetching (to fetch the `title`).

**2nd Not working scenario (when missing required field)**

If `title` field is `required` in schema, then 2nd query returns `[ null ]`. Cached result seems correct. But results aren't marked as `stale` and refetching isn't done as in the 1st scenario.

**Expected behavior**
Results should be marked as stale and refetched (2nd scenario).

**Actual behavior**
Results are not stale and not refetched (2nd scenario).

<!--
  Your issue will be addressed much faster if you include a
  reproduction. Here are some templates to help you create one:
  - client: https://codesandbox.io/s/urql-issue-template-client-iui0o
  - server: https://codesandbox.io/s/urql-issue-template-server-0ufyz
-->

### Additional contract requirements

- For the required-field case, the result's `operation.context.meta.cacheOutcome` must be `'partial'`.
- For the initial complete query, `operation.context.meta` must be `undefined`.
