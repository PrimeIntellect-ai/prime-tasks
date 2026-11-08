`immutable-data`: Map Support
## Suggestion
Thank you for this amazing linter, this has helped us keep our codebase maintainable and our data flows easy to understand! I have a request: currently `immutable-data` supports array and disallows modifications. When it comes to other similar datatypes like Maps, the linter doesn't  seem to have rules that prevent modifications.

Example with `immutable-data` set to `error`:
```ts
export const value = new Map();
value.set('foo', 'bar'); // no errors.
```

If I missed it, can you please point me in the right direction? Thank you!
