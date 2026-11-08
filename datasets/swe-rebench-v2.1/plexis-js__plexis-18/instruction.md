Feature request: `toLower / toFirstLower / decapitalize`
Converts the first character of the input text to lowercase. If the second parameter is true, the method converts the rest of the subject to lower case.

```javascript
  @param {String} text
  @param {Boolean} isLowercase
```

**Example usage**

```javascript
import toLower from '@plexis/to-lower';
toLower('foo Bar');
// => foo Bar

toLower('FOO Bar');
// => fOO Bar

toLower('fOO Bar', true);
// => foo bar
```

**Aliases**

```javascript
import toLower from '@plexis/to-lower';
import {toLower, toFirstLower, decapitalize } from 'plexis';
```
