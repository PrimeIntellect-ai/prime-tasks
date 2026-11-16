Proposal for top-level extends
Forgive me if this has already been asked; I checked but didn't find a similar issue.

Why is `extend` a method of Struct constructors?  For example:

```javascript
const A = t.struct({
    a: t.String
}, 'A');

const B = t.struct({
    b: t.String
}, 'B');

const C = t.struct({
    c: t.Number
}, 'C');

const D = C.extend([A, B], 'D');

const d = new D({
    a: 'a',
    b: 'b',
    c: 4
});

console.log(d instanceof D); // true
console.log(d instanceof C); // false

```

Why should D = C.extend, when the inheritance chain isn't preserved?  The same is true for A and B.

I understand why we **wouldn't** want it to work that way, but given that, what if we had:

```javascript
const D = t.extend([A,B,C], 'D');
```
(feel free to replace `extend` with `mix` or even `t.struct.combine` if the other two are too closely named to other methods)

That way, when I want an intersection of structs, so to speak, I don't have to pick a "base" struct to extend from?  Maybe it's a bit of an arbitrary or trivial pain point, but I think there's a bit of a mental disconnect between what's actually happening, and the implication of extend belonging to a Struct constructor.

I'd be happy to take a stab at a putting together a pull request if you'd like.

### Additional contract requirements

- Add a public function `t.struct.extend(mixins, name)` exported from `lib/struct.js` as `t.struct.extend`.
- `mixins` is an array whose items are either object literals defining additional properties or existing `t.struct` types.
- `name` is a string assigned to the resulting type's `.meta.name`.
- The function returns a new Tcomb struct type whose `.meta.props` contains the union of all property definitions from the supplied mixins.
