Type inference not working when default type parameter is used in trait
Example:

```rust
struct A;

trait Op<RHS=Self> {
    type Output;

    fn do_op(self, rhs: RHS) -> Self::Output;
}

impl Op for A {
    type Output = bool;

    fn do_op(self, rhs: Self) -> Self::Output {
        true
    }
}

impl std::ops::Sub for A {
    type Output = bool;
    fn sub(self, rhs: Self) -> Self::Output {
        true
    }
}

fn test() {
    let x = A;
    let y = A;
    let r = x.do_op(y);

    let x = A;
    let y = A;
    let r = x - y;
}

```

In both cases the type for variable r is not inferred correctly. It resolves to e.g. *Op::Output<A, A>*.

As soon as the impl block specifies the RHS type parameter, everything works just fine:


```rust
struct A;

trait Op<RHS=Self> {
    type Output;

    fn do_op(self, rhs: RHS) -> Self::Output;
}

impl Op<Self> for A {
    type Output = bool;

    fn do_op(self, rhs: Self) -> Self::Output {
        true
    }
}

impl std::ops::Sub<Self> for A {
    type Output = bool;
    fn sub(self, rhs: Self) -> Self::Output {
        true
    }
}

fn test() {
    let x = A;
    let y = A;
    let r = x.do_op(y);

    let x = A;
    let y = A;
    let r = x - y;
}

```

Both cases infer r to be of type bool.

Edit:

Type inference for overloaded operators in *std::ops* does not actually work in RA. I have a branch for that, which is currently pretty useless. If we can fix the default type parameter problem in traits, it will work just fine (I guess).

### Additional contract requirements

When a trait type argument is omitted and has a declared default, resolving an associated type output from a trait-method call must use that default.
