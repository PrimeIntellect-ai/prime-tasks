Performance: Component Re-rendered because of hook changes.
Make sure the state returned from the reducer is not a different object that equals by value but different by reference from the previous state:

![image](https://user-images.githubusercontent.com/17661697/70374958-27b02500-18f9-11ea-9097-52affdcc3d39.png)

### Additional contract requirements

- The response object returned by the hook must be referentially stable: re-rendering the component must return the same object reference (not a new object that equals by value), including when the underlying `data`, `error`, or `isValidating` values change.
