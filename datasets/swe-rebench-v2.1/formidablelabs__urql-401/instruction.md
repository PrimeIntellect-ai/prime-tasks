operationName is never set by fetchExchange
**Describe the bug**
When executing a query via urql, our graphql server (apollo) is not receiving an `operationName`. When using the apollo playground, even individual queries have an `operationName` computed.

I understand that `operationName` is only required for multiple operations in a query (as per https://graphql.org/learn/serving-over-http/#post-request) but from my experience, even multiple queries inside a transaction isn't setting it.

**Steps to reproduce**
Steps to reproduce the behavior:
1. Create an apollo graphql server
2. As part of it, create an extension (such as this one) and consume it in the `extensions` of apollo config
``` js
import { GraphQLExtension } from 'graphql-extensions';

export default class CustomExtension extends GraphQLExtension {
  requestDidStart({ operationName }) {
    console.log(`operation name is "${operationName}"`);
  }
}
```
3. fire a call to the apollo server and you observe the server console

**Expected behavior**
The `operationName` should be picked intelligently such as the name of the query being executed (as apollo client does)

**Actual behavior**
The `operationName` parameter is `undefined`

**Additional context**
n/a
