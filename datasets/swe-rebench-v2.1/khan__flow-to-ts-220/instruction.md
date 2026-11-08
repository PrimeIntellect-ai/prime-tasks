$Exact utility type
> $Exact<{name: string}> is a synonym for {| name: string |} as in the Object documentation.
https://flow.org/en/docs/types/utilities/#toc-exact

So Foo and Bar should result in the same output below:

```js
// @flow
import type {Node} from 'react';

type Foo<T> = $Exact<{
    bar: T
}>;

type Bar<T> = {|
    bar: T
|};
```

But the following is returned:

```
import {Node} from "react";

type Foo<T> = $Exact<{
    bar: T;
}>;

type Bar<T> = {
    bar: T;
};
```

https://flow-to-ts.netlify.com/#code=Ly8gQGZsb3cKaW1wb3J0IHR5cGUge05vZGV9IGZyb20gJ3JlYWN0JzsKCnR5cGUgRm9vPFQ+ID0gJEV4YWN0PHsKICAgIGJhcjogVAp9PjsKCnR5cGUgQmFyPFQ+ID0ge3wKICAgIGJhcjogVAp8fTsK&prettier=1&semi=1&singleQuote=0&tabWidth=4&trailingComma=all&bracketSpacing=0&arrowParens=avoid&printWidth=80&inlineUtilityTypes=0

### Additional contract requirements

- `$Exact<T>` is replaced by its type argument `T` for any type `T`, not only inline object types. For example, `$Exact<C>` converts to `C`.
