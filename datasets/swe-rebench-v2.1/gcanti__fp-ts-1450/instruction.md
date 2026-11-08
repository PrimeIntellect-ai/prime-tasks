Add Array#fromPredicate and Array#fromOption
```ts
export function fromPredicate<A, B extends A>(refinement: Refinement<A, B>): (a: A) => Array<B>
export function fromPredicate<A>(predicate: Predicate<A>): (a: A) => Array<A>
export function fromPredicate<A>(predicate: Predicate<A>): (a: A) => Array<A> {
  [HIDDEN]
}
```

and

```ts
export function fromOption<A>(ma: Option<A>): Array<A> {
  [HIDDEN]
}
```

### Additional contract requirements

- `Array#fromPredicate`: For either overload, the returned function produces a singleton array containing the input when the predicate or refinement accepts it, and an empty array otherwise.
- `Array#fromOption`: Convert `Some(a)` to a singleton array containing `a`, and `None` to an empty array.
