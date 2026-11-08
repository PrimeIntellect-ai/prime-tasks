Remove duplicates names in `no-duplicates` autofix
Let’s say we have the following content:

```js
import { a, b } from 'module'
import { a, c } from 'module'
```

The `import/no-duplicates` rule will report this, then perform the following autofix:

```js
import { a, b, a, c } from 'module'
```

I would expect it to remove duplicates, so the output would be:

```js
import { a, b, c } from 'module'
```

In my experience this is common when resolving merge conflicts if two branches added a new member to the import statement. It’s easy to _Accept both changes_, then let ESLint autofix resolve any issues with the imports. However, afterwards one has to remove the duplicates manually.
