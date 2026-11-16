clearHistory breaks if there have been unmatched calls
```typescript
import fetchMock from "fetch-mock";

describe(fetch-mock", () => {
 it("should avoid real fetch when enabled, even if no mocks set", async () => {
    fetchMock.mockGlobal();
    try {
      await expect(fetch("https://example.com")).rejects.toBeInstanceOf(Error);
      fetchMock.clearHistory();  // Error
    } finally {
      fetchMock.unmockGlobal();
    }
  });
});
```

```
__tests__/fetch-mock.test.ts
  fetch-mock
    ✕ should avoid real fetch when enabled, even if no mocks set (2 ms)

  ● fetch-mock › should avoid real fetch when enabled, even if no mocks set

    TypeError: Cannot read properties of undefined (reading 'reset')

      31 |     try {
      32 |       await expect(fetch(testUrl)).rejects.toBeInstanceOf(Error);
    > 33 |       fetchMock.clearHistory();  // Error
         |                 ^
      34 |     } finally {
      35 |       fetchMock.unmockGlobal();
      36 |     }

      at node_modules/fetch-mock/dist/esm/CallHistory.js:19:52
          at Array.forEach (<anonymous>)
      at CallHistory.clear (node_modules/fetch-mock/dist/esm/CallHistory.js:19:23)
      at FetchMock.clearHistory (node_modules/fetch-mock/dist/esm/FetchMock.js:83:26)
      at Object.<anonymous> (__tests__/fetch-mock.test.ts:33:17)
```
