Issue parsing nullable arrays on Docblocks
First of all, thank you very much for maintaining this and releasing the last version that quick.
There is just another tricky type that doesn't seem to be correctly parsed, nullable arrays.

DocBlocks like this one raise an exception as are not considered nullable arrays, but the whole `string[]` gets taken as the type:
```php
/**
 * string[]|null
 */
$myVAr
```

I've created some [failing tests in this commit](https://github.com/namelivia/JsonMapper/commit/3f9d7d9e7b328b514833ca771ac346a69792816a), so its easier to debug.
Again, thank you for your support!
