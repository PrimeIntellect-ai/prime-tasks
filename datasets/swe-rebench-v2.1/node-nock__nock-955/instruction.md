allowUnmocked causes no requests to match when query is specified
``` javascript
var nock=require('nock'),
request=require('request');

nock('https://www.google.com',
    { allowUnmocked: true })
    .log(console.log)
    .get("/abc")
    .query({'user':'fred'})
    .reply(200, "Match!")

request('https://www.google.com/abc?user=fred', function (error, response, body) {
    if (!error && response.statusCode == 200) {
        console.log(body);
    } else{
        console.log(error ? "error: " + error : "response.statusCode: "+ response.statusCode);
    }
});
```

With the code above, my request does NOT match and goes to google.com.
$ node nockTest.js
response.statusCode: 404

By changing allowUnmocked to false, I get:

$ node nockTest.js
matching https://www.google.com:443?user=fred to GET https://www.google.com:443/abc with query({"user":"fred"}): true
Match!

I am able to work around this and keep allowUnmocked=true by [HIDDEN]. Is this a bug or am I missing something here? Thanks!

### Additional contract requirements

- When `allowUnmocked` is enabled, a request that satisfies an interceptor's path and configured query matcher must be handled by that interceptor. A request with a query that does not satisfy the configured matcher must not be handled by it.
- Regular-expression path matchers must remain able to match query-bearing request targets, including when the expression explicitly includes query syntax.
