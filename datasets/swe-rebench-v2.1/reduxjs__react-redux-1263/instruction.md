consecutive dispatches can lead to incorrect update order
**Do you want to request a _feature_ or report a _bug_?**

bug

**What is the current behavior?**

When two dispatches are performed consecutively inside a batch and the second dispatch does not change the result of `mapState` of a connected component, it will notify its children of the second dispatch before it re-renders itself, leading to potential stale props in the children.

This [sandbox](https://codesandbox.io/s/p3q6xzqq5j) demonstrates the issue.

**What is the expected behavior?**

Even with consecutive dispatches react-redux should ensure top-down update order.

**Which versions of React, ReactDOM/React Native, Redux, and React Redux are you using?  Which browser and OS are affected by this issue? Did this work in previous versions of React Redux?**

This bug affects versions >=7.0.0 of react-redux.
