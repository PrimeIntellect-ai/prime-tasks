async
Creates async interface from generator. https://www.promisejs.org/generators/

```js
const responsesP = async(function *() {
  const response1 = yield request('http://localhost:8000');
  const response2 = yield request('http://localhost:8000/2');

  return { response1, response2 };
});

responsesP().then(console.dir);
```
Yield delegation and recursion delegatin must be tested too to guarantee correctness of the implementation.
