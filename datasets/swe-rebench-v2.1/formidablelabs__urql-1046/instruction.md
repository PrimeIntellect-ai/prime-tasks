svelte: variables reactivity
urql version & exchanges:

```json
"@urql/exchange-graphcache": "3.1.3",
"@urql/svelte": "https://pkg.csb.dev/FormidableLabs/urql/commit/4550be11/@urql/svelte",
"graphql": "15.3.0",
"graphql-tag": "2.11.0",
"svelte": "3.29.0",
```

**Steps to reproduce**

1. Start the server opening this page: https://codesandbox.io/s/apollo-server-urql-svelte-crud-h1pcl
1. Open Incognito browser session
1. Go to reproduction: https://77lev.csb.app/
1. Click on "Todos list"
1. Change `first` value using the only input available

**Expected behavior**

New API call on each change

**Actual behavior**

No API call at all

---

If you go [here](https://codesandbox.io/s/urql-svelte-100-variables-reactivity-77lev?file=/List.svelte) you can find this:

```js
// THIS DOESN'T WORK
$: {
  console.log("todos.variables BEFORE:", todos.variables);
  todos.variables.input.first = first;
  console.log("todos.variables AFTER:", todos.variables);
}

// THIS WORKS
// $: {
//   console.log("todos.variables BEFORE:", todos.variables);
//   todos.variables = { ...todos.variables, input: { first } };
//   console.log("todos.variables AFTER:", todos.variables);
// }
```

The second works but is too complicated. **You can imagine when there are so many variables to consider.**

Is this the correct way? Am I wrong?

Can you suggest something alternative?

**Additional**

[CodeSandBox client project](https://codesandbox.io/s/urql-svelte-100-variables-reactivity-77lev?file=/List.svelte)
[CodeSandBox server project](https://codesandbox.io/s/apollo-server-urql-svelte-crud-h1pcl)

### Additional contract requirements

- The request passed as the first argument to the client's `executeQuery` must include a `context` property whose value is the store's context, including `undefined` when no context is set.
- Calling `store.set(value)` with the store's own current state (`value === state`) is treated as an empty update: it must not throw and must not change the store's `query`, `variables`, or `context`.
