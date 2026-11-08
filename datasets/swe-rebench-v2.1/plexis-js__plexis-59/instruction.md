Feature request: `distance`
This method calculates the [Levenshtein Distance](https://en.wikipedia.org/wiki/Levenshtein_distance)  between two strings.

```javascript
@param {String} [fromStr]
@param {String} [toStr]
@returns {Number} The Levenshtein distance
```

**Example usage**

```javascript
import distance from '@plexis/distance';
distance('book', ''back') // => 2
distance('black', 'back') // => 1
distance('Foo', 'Bar') // => 3
```

**Aliases**

```javascript
import distance from '@plexis/distance';
import {distance, calcLevenshtein, levenshtein} from 'plexis';
```
