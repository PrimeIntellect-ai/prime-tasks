spyOn.returnValues transformation uses incorrect jest mock function
Calls to `returnValues` are currently transformed into a series of `mockReturnValue` which causes an issue in Jest since only the last call of mockReturnValue gets applied. Using [`mockReturnValueOnce`](https://jestjs.io/docs/mock-function-api#mockfnmockreturnvalueoncevalue) seems to be more appropriate.

`spyOn(stuff).and.returnValues(1,2,3);`

transformed into:

`jest.spyOn(stuff).mockReturnValue(1).mockReturnValue(2).mockReturnValue(3);
// calling stuff always returns 3
`

proposal:

`jest.spyOn(stuff).mockReturnValueOnce(1).mockReturnValueOnce(2).mockReturnValueOnce(3);`
