The new reflection parser fails on hooks example
**Describe the bug**
The example _start-hooks_ doesn't work with the new reflection parser.

**To Reproduce**
- Go to examples/2-advanced/1-start-hooks
- `npm install`
- `npm run build`
- `npm run start`

Jitar fails to start.

```ts
import { startClient } from '/jitar/client.js';
const client = await startClient('client');
const { default: sayBoth } = await client.import('./greetings/sayBoth.js');
const message = await sayBoth('John', 'Doe');
alert(message);
```

The TypeScript above doesn't get parsed. It fails on the word _default_.
