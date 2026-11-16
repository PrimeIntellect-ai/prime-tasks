Feature: `tail / rest / last / pop`
Extracts the last length characters from the input text.

```javascript
  tail(); // => ''
  tail('Hello'); // => 'o'
  tail('Hello', 2); // => 'lo'
  tail('Hello', 100); // => 'Hello'
```

**Aliases**

```javascript
import tail from '@plexis/tail';
import {tail, rest, last, pop} from 'plexis';
```
