Cannot Page will Nullable Nested Objects:  TypeError: Cannot set property '__typename' of null
urql: 2.3.0 +
Exchanges: @urql/exchange-graphcache, fetch

**Steps to reproduce**

1. Setup a client with normalized cache and fetch.
2. Setup relayPaging for data that contains a nullable object type.
3. Fetch page 1
4. Fetch page 2 (fails)

I have a simple test, it will use `relayPagination` and fetch the first two pages.
My code is slightly anomyzed from the real prod code but looks like

```ts
import {
  createClient,
  fetchExchange,
  OperationContext,
  Exchange
} from "urql";
import {
  Query,
  QueryVariables,
  Document
} from "generated/graphql"; //Our generated query and variables
import {DocumentNode, IntrospectionQuery} from "graphql";
import {PgHeaders} from "./playgroundheaders";
import introspection from "generated/introspection.json";
import { cacheExchange } from "@urql/exchange-graphcache";
import {CacheExchangeOpts} from "@urql/exchange-graphcache/dist/types/cacheExchange";
import {relayPagination} from "@urql/exchange-graphcache/extras";
// @ts-ignore
const schema: IntrospectionQuery = introspection as IntrospectionQuery;

const cacheExchangeOpts: CacheExchangeOpts = {
  schema,
  keys: {
      //We have some intentionally null keys for embedded data
  },
  resolvers: {
    Query: {
      indicators: relayPagination({
        mergeMode: "outwards"
      })
    }
  }
};
const setupReal = () => {
  const url = "<!--our host -->"
  const exchanges: Array<Exchange> = [
    cacheExchange(cacheExchangeOpts),
    fetchExchange
  ]
  const client = createClient({
    url,
    requestPolicy: "network-only", //Force paging tests to wait for a response, the real will give partial results first.
    fetchOptions: {
      headers: {
        ...PgHeaders //throw our auth headers on
      }
    },
    fetch: (input, init) => {
      console.log("Request");
      return fetch(input, init).then(reso => {
        console.log("answered");
        return reso;
      });
    },
    exchanges
  })
  //Query helper alias for test
  function query<Q = any, V extends object = {}>(query: DocumentNode | string, variables?: V, context?: Partial<OperationContext>) {
    return client.query<Q, V>(query, variables, context).toPromise()
  }
  return {client, query}
}
test("Simple test", async () => {
  const { query } = setupReal()
  const variables: QueryVariables = {
    //Setup variables
  }
  const res = await query<Query, QueryVariables>(Document, variables)
  //50 is our default page size.
  expect(res.data?.indicators?.edges.length).toBeGreaterThanOrEqual(50);
  //Nab page 2
  const after = res?.data?.indicators?.pageInfo.endCursor;
  const res2 = await query<Query, QueryVariables>(Document, {
    ...variables,
    after
  }) //ERROR HAPPENS HERE
  expect(res2.data?.indicators?.edges.length).toBeGreaterThan(51);
}, 20000)
```


The query is  like

```graphql
query testQuery($input: InputType!, $after: String) {
  indicators(input: $input, after: $after) {
    count
    pageInfo {
        endCursor
        hasNextPage
    }
    edges {
      cursor
      node {
        ...staticFields
        nullableObject {
            prop1
        }
      }
    }
  }
}
```

Type definition like

```
Query{
  indicators(input: InputType, after: String, first: Int): IndicatorConnection!
}
type IndicatorConnection {
  edges: [IndicatorEdge!]!
  pageInfo: PageInfo!
  count: Int!
}
type IndicatorEdge {
  cursor: Cursor!
  node: Indicator!
}
type Indicator {
  id: ID!
  nullableObject: NullableObject
}
```


Output in 2.2.2 (test passes)
```
/home/gsporie/.nvm/versions/node/v12.8.1/bin/node --require /snap/intellij-idea-ultimate/217/plugins/JavaScriptLanguage/helpers/jest-intellij/lib/jest-intellij-stdin-fix.js /home/gsporie/IdeaProjects/glass-review/node_modules/react-scripts/bin/react-scripts.js test --colors --reporters /snap/intellij-idea-ultimate/217/plugins/JavaScriptLanguage/helpers/jest-intellij/lib/jest-intellij-reporter.js --verbose --runTestsByPath /home/gsporie/IdeaProjects/glass-review/src/polygraphql/__integration__/graphqlClient.test.ts
  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered
```

Output in 2.3.0 (fails)

```
  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered


TypeError: Cannot set property '__typename' of null

    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:671:18)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:469:12)
    at resolveLink (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:339:26)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:469:12)
    at resolveLink (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:339:26)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:421:9)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:397:27)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:325:24)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:422:9)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:300:26)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:95:9)
    at read (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/operations/query.ts:65:18)
    at query (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/src/cacheExchange.ts:239:27)
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:759:56
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:492:42
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:492:42
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:1027:26
    at next (/home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:108:24)
    at next (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/core/src/exchanges/fetch.ts:125:23)
```


Output 2.4.0

```
  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:52
    Request

  console.log src/polygraphql/__integration__/graphqlClient.test.ts:54
    answered


TypeError: Cannot set property '__typename' of null

    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:710:20)
    at resolveLink (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:775:30)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:726:169)
    at resolveLink (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:775:30)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:726:169)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:759:62)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:747:27)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:726:66)
    at resolveResolverResult (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:759:90)
    at readSelection (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:721:45)
    at read (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:655:63)
    at query (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:647:7)
    at C (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:937:67)
    at g (/home/gsporie/IdeaProjects/glass-review/node_modules/@urql/exchange-graphcache/dist/urql-exchange-graphcache.js:828:28)
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:759:56
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:748:28
    at b (/home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:865:14)
    at Array.forEach (<anonymous>)
    at b (/home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:864:77)
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:492:42
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:492:42
    at /home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:1027:26
    at next (/home/gsporie/IdeaProjects/glass-review/node_modules/wonka/dist/wonka.js:108:24)
    at next (/home/gsporie/IdeaProjects/glass-review/node_modules/urql/node_modules/@urql/core/src/exchanges/fetch.ts:125:23)
```

**Expected behavior**

I expect it to page successfully.

This test will pass in 2.2.2, but fails in 2.3.0+


**Actual behavior**

A type error is throw from the cache exchange.

### Additional contract requirements

- A read that follows a prior selection which set a nested result field to `null` must not throw. The read completes and returns a non-null result.
