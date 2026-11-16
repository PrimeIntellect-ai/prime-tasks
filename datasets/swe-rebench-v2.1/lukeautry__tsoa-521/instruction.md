validateUnion overwriting params with undefined
## Sorting

* **I'm submitting a ...**
  - [x] bug report
  - [ ] feature request
  - [ ] support request

* I confirm that I
  - [x] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Expected Behavior
Trying to validate an array of a union of discriminated types results in only the discriminator of the last subschema to be generated to be correctly passed.

```ts
interface PetStore {
   animals: Array<Cat | Dog>;
}
interface Cat {
   type: 'cat';
   height: number;
}
interface Dog {
   type: 'dog';
   weight: number;
}
```

The following JSON object should be correctly passed to the controller method:

```json
{
   "animals": [
      { "type": "cat", "height": 100 },
      { "type": "dog", "weight": 20 }
   ]
}
```

## Current Behavior
What currently happens is the `type` property is overwritten by `undefined` unless its value is that of the last subschema passed of the union. The actual object passed to the controller method:

```ts
{
   "animals": [
      { "type": undefined, "height": 100 },
      { "type": "dog", "weight": 20 }
   ]
}
```

## Possible Solution
I've already written a PR ready to fix this that seems to pass all the tests except one that I've adapted since it makes sense either way.

The changes are here https://github.com/Passiverecords/tsoa/commit/d03e401066a16eb8e52ea9b36c8f216667785a87

## Context (Environment)
Version of the library: 2.5.7
Version of NodeJS: 12.7.0
* Confirm you were using yarn not npm: [x]

## Breaking change?
I am not 100% what implications the changes reflected by the test have... should values that do not exist be explicitly passed as undefined? As far as JS goes, I assume it shouldn't impact anyone.
