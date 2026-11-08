base trait method not resolved when using impl in return position
<!--
Troubleshooting guide: https://rust-analyzer.github.io/manual.html#troubleshooting
Forum for questions: https://users.rust-lang.org/c/ide/14

Before submitting, please make sure that you're not running into one of these known issues:

 1. local imports (`use` statements) don't work: #1165
 2. local items don't work: #1559
 3. on-the-fly diagnostics are mostly unimplemented (`cargo check` diagnostics will be shown when saving a file)
 4. some settings are required for procedural macro and build script support (`rust-analyzer.cargo.loadOutDirsFromCheck`, `rust-analyzer.procMacro.enable`): #6448
 5. some platform-specific imports are not resolved: #6038
 6. the official `rust-lang.rust` VS Code extension conflicts with `rust-analyzer`: #6463

Otherwise please try to provide information which will help us to fix the issue faster. Minimal reproducible examples with few dependencies are especially lovely <3.
-->
Code that reproduces the issue:
```rust
fn elements_iter() -> impl Iterator<Item = usize> {
    [].iter().copied()
}

fn elements_exacte_size_iter() -> impl ExactSizeIterator<Item = usize> {
    [].iter().copied()
}

fn test() {
    for x in elements_iter() {}
    //  ^ is correctly inferred to be `usize`
    for x in elements_exacte_size_iter() {}
    //  ^ is not inferred
}
```
After investigating in the rust-analyzer source and playing around with a test in `crates/hir_ty/src/tests/traits.rs` I found out that inference works when it's an argument:
```rust
fn foo(xs: impl ExactSizeIterator<Item = usize>) {
    for x in xs {}
    //  ^ inferred `usize`
}
fn bar<I: ExactSizeIterator<Item = usize>>(xs: I) {
    for x in xs {}
    //  ^ inferred `usize`
}
```
This is the test:
```rust
#[test]
fn super_trait_assoc_type_impl_return() {
    check_infer(
        r#"
        trait Base {
            type Item;
            fn foo(self) -> Self::Item;
        }

        trait Super : Base {}

        fn base1() -> impl Base<Item = usize> { loop {} }
        fn super1() -> impl Super<Item = usize> { loop {} }

        fn test(base2: impl Base<Item = usize>, super2: impl Super<Item = usize>) {
            base1().foo();
            super1().foo();
            base2.foo();
            super2.foo();
        }
        "#,
        expect![[r#"..."#]],
    );
}
```

which at the moment gives:
```
39..43 'self': Self
124..135 '{ loop {} }': !
126..133 'loop {}': !
131..133 '{}': ()
176..187 '{ loop {} }': !
178..185 'loop {}': !
183..185 '{}': ()
197..202 'base2': impl Base<Item = usize>
229..235 'super2': impl Super<Item = usize>
263..352 '{     ...o(); }': ()
281..286 'base1': fn base1() -> impl Base<Item = usize>
281..288 'base1()': impl Base<Item = usize>
281..294 'base1().foo()': usize
300..306 'super1': fn super1() -> impl Super<Item = usize>
300..308 'super1()': impl Super<Item = usize>
300..314 'super1().foo()': {unknown}
320..325 'base2': impl Base<Item = usize>
320..331 'base2.foo()': usize
337..343 'super2': impl Super<Item = usize>
337..349 'super2.foo()': usize
```
