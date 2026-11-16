Failure to parse some usages of Flow $Call (Unexpected token, expected ",")
Sucrase fails to parse some usages of the type helper `$Call` inside Flow code :

Example of code failing :

```js
// @flow

type Account = $PropertyType<
  $Call<<T>($ReadOnlyArray<T>) => T>,
  'account'
>
```

Demo :
* [Sucrase (failing)](https://sucrase.io/#transforms=flow&code=%2F%2F%20%40flow%0A%0Atype%20Account%20%3D%20%24PropertyType%3C%0A%20%20%24Call%3C%3CT%3E(%24ReadOnlyArray%3CT%3E)%20%3D%3E%20T%3E%2C%0A%20%20'account'%0A%3E)
* [Flow compiler (accepted)](https://flow.org/try/#0PQKgBAAgZgNg9gdzCYAoVAXAngBwKZgCCAxsXAK4B2GYAvGACQAKATnPi9gCq54A8qMIwDCAQxgw+fLgD4AFAwBKeUQBMA8pRhZCLFqKzSZASjoywsgDSCwAclGkK1W6hmogA)
