Condition in body removes contextual type of later return statement
```ts
declare function useMemo<T>(func: () => T): T;

function getPredicate(alwaysTrue: boolean) {
    const predicate: ((input: string) => boolean) = useMemo(() => {
        if (alwaysTrue) {
            return () => true;
        }

        return input => input.length > 0;
    });

    return predicate;
}
```

`tsc` issues no error, `tsgo` issues:

```
src/index.ts:8:12 - error TS7006: Parameter 'input' implicitly has an 'any' type.

8     return input => input.length > 0;
             ~~~~~
```
