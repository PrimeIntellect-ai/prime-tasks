takeWhile and dropWhile
The Ramda functions [takeWhile](http://ramdajs.com/docs/#takeWhile) and [dropWhile](http://ramdajs.com/docs/#dropWhile) should both have the type signature:
```javascript
(a -> Boolean) -> List a -> List a
```

I mentioned `takeUntil` and `dropUntil` in the Gitter room, but thinking on it more they don't bring much to the table (the way I was thinking of them):

```javascript
const takeUntil = pred => S.takeWhile(S.complement(pred));
```
