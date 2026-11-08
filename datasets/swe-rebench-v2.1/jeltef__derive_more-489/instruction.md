`Self: 'static` bound gets mistakenly applied to references
In the following code, the `Self: 'static` bound gets copied to the derived impl `TryFrom<&mut Foo<V>> for (&mut Wrapper<V>) where Self: 'static`, which changes the bound from `Foo<V>: 'static` to `&mut Foo<V>: 'static`.

```rs
use derive_more;

#[derive(Debug)]
pub struct Wrapper<V>(V);

#[derive(derive_more::TryInto)]
#[try_into(ref, ref_mut)]
pub enum Foo<V> where Self: 'static {  // This line fails
// pub enum Foo<V> where Foo<V>: 'static {  // This line succeeds, after explicitly changing `Self` to `Foo<V>`
    V(Wrapper<V>),
}

fn main() {
    let x = Foo::<u8>::V(Wrapper(2));
    let u8ref: &Wrapper<u8> = (&x).try_into().unwrap();
    println!("{u8ref:?}");
}
```

And the resulting build fails with

```
error[E0597]: `x` does not live long enough
  --> src/main.rs:20:31
   |
19 |     let x = Foo::<u8>::V(Wrapper(2));
   |         - binding `x` declared here
20 |     let u8ref: &Wrapper<u8> = (&x).try_into().unwrap();
   |                               ^^^^-----------
   |                               |
   |                               borrowed value does not live long enough
   |                               argument requires that `x` is borrowed for `'static`
21 |     println!("{u8ref:?}");
22 | }
   | - `x` dropped here while still borrowed
```

https://www.rustexplorer.com/b#LyoKW2RlcGVuZGVuY2llc10KZGVyaXZlX21vcmUgPSAiKiIKKi8KCnVzZSBkZXJpdmVfbW9yZTsKCiNbZGVyaXZlKERlYnVnKV0KcHViIHN0cnVjdCBXcmFwcGVyPFY+KFYpOwoKI1tkZXJpdmUoZGVyaXZlX21vcmU6OlRyeUludG8pXQojW3RyeV9pbnRvKHJlZiwgcmVmX211dCldCnB1YiBlbnVtIEZvbzxWPiB3aGVyZSBTZWxmOiAnc3RhdGljIHsgIC8vIFRoaXMgbGluZSBmYWlscwovLyBwdWIgZW51bSBGb288Vj4gd2hlcmUgRm9vPFY+OiAnc3RhdGljIHsgIC8vIFRoaXMgbGluZSBzdWNjZWVkcywgYWZ0ZXIgZXhwbGljaXRseSBjaGFuZ2luZyBgU2VsZmAgdG8gYEZvbzxWPmAKICAgIFYoV3JhcHBlcjxWPiksCn0KCmZuIG1haW4oKSB7CiAgICBsZXQgeCA9IEZvbzo6PHU4Pjo6VihXcmFwcGVyKDIpKTsKICAgIGxldCB1OHJlZjogJldyYXBwZXI8dTg+ID0gKCZ4KS50cnlfaW50bygpLnVud3JhcCgpOwogICAgcHJpbnRsbiEoInt1OHJlZjo/fSIpOwp9

### Additional contract requirements

- The `Into` derive must resolve `Self` in a field type to the type the derive is applied to. Deriving `Into` for a struct with a single field of type `[u8; Self::SIZE]`, where `SIZE` is an associated constant of that struct, must allow a value of the struct to be converted into its contained `[u8; <Struct>::SIZE]` array by calling `.into()`.
