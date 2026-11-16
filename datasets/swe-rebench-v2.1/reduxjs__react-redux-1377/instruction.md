Provider uses previous store for one additional render when store changes
**Do you want to request a _feature_ or report a _bug_?**

Bug

**What is the current behavior?**

If a the `store` passed to a `Provider` changes the `store` in `ReactReduxContext` does not update until the next render.  This is causing me an issue the `children` are changing, causing the to crash when trying to `mapStateToProps` in that additional render.

[Sandbox.](https://codesandbox.io/s/thirsty-cherry-f49el)

Note: this is a contrived example to to show how this occurs, but I have an real world case using React Router V5 that has the same issue.

Also Note: my use case is not to have a distinct store per page, but actually using `redux-subspace` to create a virtual sub-store per page.  Again, I didn't bother with this detail for the example as it occurs with real stores too.

**What is the expected behavior?**

I would expect that if `Provider` permits me to change the store, that a `connect`ed component below it would not crash when rendering.  I believe the root of the issue is the fact that [the store is not updated in the `Providers`'s state until `componentDidUpdate`](https://github.com/reduxjs/react-redux/blob/master/src/components/Provider.js#L38-L45), but the render the would result in this update already has the new `this.props.children` value.

I do concede that this is a pretty niche use case, and may not be the highest priority to fix (assuming you agree that it is an issue at all).

**Which versions of React, ReactDOM/React Native, Redux, and React Redux are you using?  Which browser and OS are affected by this issue? Did this work in previous versions of React Redux?**

```json
"react": "16.8.6",
"react-dom": "16.8.6",
"redux": "4.0.4"
"react-redux": "7.1.0",
```
