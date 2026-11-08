Incorrect Flow type removal for imports
The following import statement:

```js
import { Foo, type Baz } from "../module";
```

is converted wrongly into:

```js
import { Foo, Baz } from "../module";
```

Flow introduced this type syntax in imports in version 0.38.0 and it does not seem to be supported in prettier yet.
