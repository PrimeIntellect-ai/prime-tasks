(graphcache) - Stale result with suspense in development mode
This seems to be related to #1253. I've mounted a component that has a paginated list in the form of (last: 20, before: X) which renders properly. After the list is rendered I trigger a state change so that the component re-renders and fetches (last 20, before: Y). I can see in the network tab that the data is being fetched properly. Logging the output of the `useQuery` hook also shows the element rendering after the data is fetched with the correct data but then being re-rendered and using the previous data.

Disabling suspense causes the proper list (last: 20, before: Y) to be shown. Creating a production build disables React's double-render and will show the correct list with suspense enabled and suspense disabled.

urql version & exchanges: 1.11.5, [dedupExchange, Graphcache.cacheExchange, fetchExchange, subscriptionExchange]

I pulled and built the changes from #1300 locally and ran `yarn add /path/to/local/build` to use the latest fixes. This did not resolve the issue.

**Steps to reproduce**

1. In a React development build
2. Create an urql client with suspense enabled and the graphcache
3. Create a component that renders a list of a relay connection
4. Change the cursor of the rendered list

**Expected behavior**

The component rerenders with the updated list twice

**Actual behavior**

The component rerenders with the updated list and then rerenders with the list for the old cursor

Reproduction sandbox is here: https://codesandbox.io/s/recursing-moser-nvfw5?file=/src/App.js
