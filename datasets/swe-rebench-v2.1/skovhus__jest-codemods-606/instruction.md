jasmine *.calls.reset() should be replaced by *.mockReset()
jasmine has a namespace `calls` on spies with a method called `reset()` , [see their docs](https://jasmine.github.io/api/5.2/Spy_calls.html).

## Desired behaviour
Input:
```ts
mySpy.calls.reset();
```

should be transformed to:
```ts
mySpy.mockReset();
```
