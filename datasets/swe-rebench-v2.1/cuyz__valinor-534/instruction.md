Issue with variadic parameter contains generics
After upgrade from 1.7 to 1.12, my code broke even though I didn't make any changes. I was using [`ramsey/collection`](https://github.com/ramsey/collection/) for my DTO. `UnresolvableType` was thrown, but there was no specific error message provided. After further debugging, I believe this is the cause of the error.

![image](https://github.com/CuyZ/Valinor/assets/1808758/2e244374-d7bf-4225-b9c5-b2413e36cf64)

This is the docblock of `merge` method which I'm not use anyway.

```php
/**
 * @param CollectionInterface<T> ...$collections The collections to merge.
 *
 * @return CollectionInterface<T>
 *
 * @throws CollectionMismatchException if unable to merge any of the given
 *     collections or items within the given collections due to type
 *     mismatch errors.
 */
public function merge(CollectionInterface ...$collections): CollectionInterface
```

### Additional contract requirements

- When a variadic parameter’s docblock type cannot be resolved, type resolution must return an `UnresolvableType` rather than mask the unresolved type as an array type.
