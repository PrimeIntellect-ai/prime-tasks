Differentiate `0` and undefined value of `status` parameter
It's rare case, but common enough that `fetch` can return `0` number status. Current library version (12.0.1) doesn't support `0` number and treats this value as `undefined` which leads to return status `200`.

Example:
```ts
		fetchMock.mockGlobal().postOnce({
			...baseConfig,
			response: {
				status: 0,
				body: JSON.stringify({ hello: "world" })
			}
		});
```

will return:
```
    {
      [Symbol(realm)]: { settingsObject: {} },
      [Symbol(state)]: {
        aborted: false,
        rangeRequested: false,
        timingAllowPassed: false,
        requestIncludesCredentials: false,
        type: 'default',
        status: 200,
        timingInfo: null,
        cacheState: '',
        statusText: 'OK',
        headersList: HeadersList {
          cookies: null,
          [Symbol(headers map)]: [Map],
          [Symbol(headers map sorted)]: null
        },
        urlList: [],
        body: { stream: undefined, source: '{"hello":"world"}', length: 17 }
      },
      [Symbol(headers)]: HeadersList {
        cookies: null,
        [Symbol(headers map)]: Map(2) { 'content-length' => [Object], 'content-type' => [Object] },
        [Symbol(headers map sorted)]: null
      }
    }
```

### Additional contract requirements

- When a response is configured with status `0`, its `statusText` must be `''`.
