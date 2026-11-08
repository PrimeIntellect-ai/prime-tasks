applyEach arguments position
Currently the `applyEach` and `applyEachSeries` functions have the following type signature:

``` js
async.applyEach(fns, ...args?, callback?)
```

Having a rest parameter in the middle of the arguments list is very difficult to write a type annotation for. It's currently not possible in either Flow or TypeScript, which is why you see stuff [like this](https://github.com/DefinitelyTyped/DefinitelyTyped/blob/master/async/async.d.ts#L132-L133) (I'm writing a similar type definition for Flow right now).

Would it be okay to switch the argument order around and make callback nullable so it is like this?

``` js
async.applyEach(fns, callback | null, ...args?)
```

Or use an array instead of a rest parameter?

``` js
async.applyEach(fns, args?: Array<any>, callback?)
```

### Additional contract requirements

For both `applyEach` and `applyEachSeries`, use the curried API shape: supplying the function collection and its shared arguments returns a runner function, and the optional callback is supplied to that runner. This separates the variable number of shared arguments from the optional callback, so the callback does not follow a rest parameter in the same call signature. Calling the runner without a callback returns a Promise; it resolves to the ordered results or rejects on an error. `applyEach` runs functions in parallel, while `applyEachSeries` runs them sequentially.
