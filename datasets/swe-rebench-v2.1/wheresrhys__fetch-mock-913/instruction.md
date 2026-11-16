"Body is unusable: Body has already been read" on multiple `fetch` calls when `response` parameter is a `Response` instance
```js
import fetchMock from "fetch-mock";

fetchMock
  .mockGlobal()
  .get(
    "https://www.example.com/",
    new Response(JSON.stringify({ name: "John Doe" }))
  );

const makeRequest = async () => {
  const response = await fetch("https://www.example.com/");
  const data = await response.json();
  console.log(data);
};

makeRequest(); // Ok
makeRequest(); // Error: Body is unusable: Body has already been read
```

Presumably the `Request` instance is being returned unmodified. However, the behavior is a bit confusing, and [HIDDEN]

Workaround is to pass a [Response config](https://www.wheresrhys.co.uk/fetch-mock/docs/API/route/response#response-config), [Promise](https://www.wheresrhys.co.uk/fetch-mock/docs/API/route/response#promise), or [Function](https://www.wheresrhys.co.uk/fetch-mock/docs/API/route/response#function) as the `response` parameter, as these can create a unique `Request` instance per mocked `fetch` call.

Node v22.11.0

### Additional contract requirements

- A route configured with a single `Response` instance must support multiple fetch calls. Each call must return a response whose body remains readable, including after an earlier call's body has been consumed.
