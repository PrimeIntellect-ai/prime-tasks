Unhandled rejection if an object has both a synchronous and asynchronous "Cannot return null for non-nullable field" error
Sorry about the title but it's a pretty specific scenario.

It looks like this error occurs because of how errors are handled for non-nullable fields. (I saw this with the `Cannot return null for non-nullable field` error, but it seems if the resolver throws an error it would be handled the same way.)

The problem appears to be here: https://github.com/graphql/graphql-js/blob/main/src/execution/execute.ts#L450
Let's say in the example below, the City object type has a resolver for `country`, which is asynchronous, and a resolver for `population`, which is synchronous, and they _both_ return null (which they shouldn't, of course). The resolver for the `country` field is run, and returns a promise. Then the resolver for the `population` field is run, and because it's synchronous, the error is thrown straight away, and the promise returned by the `country` resolver is discarded. When that promise eventually rejects, the process crashes with an `unhandledRejection` error.

```js
// File: testcase.mjs
import { graphql, GraphQLInt, GraphQLList, GraphQLNonNull, GraphQLObjectType, GraphQLSchema, GraphQLString } from "graphql";

process.on("unhandledRejection", reason => {
    console.error("Unhandled rejection!", reason);
});

const City = new GraphQLObjectType({
    name: "City",
    fields: {
        name: { type: new GraphQLNonNull(GraphQLString) },
        country: { type: new GraphQLNonNull(GraphQLString), resolve: () => Promise.resolve(null) },
        population: { type: new GraphQLNonNull(GraphQLInt), resolve: () => null },
    }
});

const Query = new GraphQLObjectType({
    name: "Query",
    fields: {
        cities: {
            type: new GraphQLNonNull(new GraphQLList(new GraphQLNonNull(City))),
            resolve() {
                return [{ name: "London", country: "GB", population: 8_982_000 }];
            }
        }
    }
});

const schema = new GraphQLSchema({
    types: [City],
    query: Query,
});

try {
    graphql(schema, `
        query {
            cities { name country population }
        }
    `).then(result => {
        if (result.errors)
            console.error("Error returned in result.errors[]:", result.errors);
        else
            console.log("Result:", result.data);
    }, error => {
        console.error("graphql() rejected:", error);
    });
} catch(err) {
    console.error("Error caught by try/catch:", err);
}
```

The output of this is:

```
Error returned in result.errors[]: [
  Error: Cannot return null for non-nullable field City.population.
      at completeValue (/home/lee/restapi/node_modules/graphql/execution/execute.js:566:13)
      at resolveField (/home/lee/restapi/node_modules/graphql/execution/execute.js:478:19)
      at executeFields (/home/lee/restapi/node_modules/graphql/execution/execute.js:292:18)
      at collectAndExecuteSubfields (/home/lee/restapi/node_modules/graphql/execution/execute.js:755:10)
      at completeObjectValue (/home/lee/restapi/node_modules/graphql/execution/execute.js:745:10)
      at completeValue (/home/lee/restapi/node_modules/graphql/execution/execute.js:597:12)
      at completeValue (/home/lee/restapi/node_modules/graphql/execution/execute.js:563:21)
      at /home/lee/restapi/node_modules/graphql/execution/execute.js:627:25
      at Array.map (<anonymous>)
      at safeArrayFrom (/home/lee/restapi/node_modules/graphql/jsutils/safeArrayFrom.js:36:23) {
    locations: [ [Object] ],
    path: [ 'cities', 0, 'population' ]
  }
]
Unhandled rejection! Error: Cannot return null for non-nullable field City.country.
    at completeValue (/home/lee/restapi/node_modules/graphql/execution/execute.js:566:13)
    at /home/lee/restapi/node_modules/graphql/execution/execute.js:475:16 {
  locations: [ { line: 3, column: 27 } ],
  path: [ 'cities', 0, 'country' ]
}
```
